import torch
import os
import io
import time
import re
import requests
import concurrent.futures
import rembg
import trimesh
import numpy as np
import json
import tempfile
import shutil
from google import genai
from google.genai import types
from dataclasses import dataclass
from typing import Optional
from urllib.parse import quote_plus, urlparse, urlunparse
from flask import Flask, request, send_file, jsonify
from flask_cors import CORS
from sf3d.system import SF3D
from sf3d.utils import remove_background, resize_foreground
from PIL import Image, ImageEnhance, ImageFilter
from contextlib import nullcontext
from pxr import Usd, UsdGeom

# --- CONFIGURATION ---
API_KEY = "AIzaSyD5eKao6gTHNddQcTgd0AvEYWkxJQZU9Pg"
client = genai.Client(api_key=API_KEY)
MODEL_ID = "gemini-2.5-flash"

# --- SELENIUM IMPORTS ---
try:
    from selenium import webdriver
    from selenium.webdriver.chrome.options import Options as ChromeOptions
    from selenium.webdriver.chrome.service import Service as ChromeService
    from webdriver_manager.chrome import ChromeDriverManager
    from bs4 import BeautifulSoup
    HAS_SELENIUM = True
except ImportError:
    print("⚠️ WARNING: Selenium/BS4 not found.")
    HAS_SELENIUM = False

app = Flask(__name__)
CORS(app)

# ==========================================
# 1. MODEL INITIALIZATION
# ==========================================
print("⏳ INITIALIZING: Loading SF3D Model...")
device = "cuda" if torch.cuda.is_available() else "cpu"
try:
    model = SF3D.from_pretrained(
        "stabilityai/stable-fast-3d",
        config_name="config.yaml",
        weight_name="model.safetensors",
    )
    model.to(device)
    model.eval()
    print(f"✅ Model loaded on {device}")
except Exception as e:
    print(f"❌ CRITICAL ERROR: Model failed to load. {e}")
    exit(1)

rembg_session = rembg.new_session()

# ==========================================
# 2. USDZ & GEMINI LOGIC
# ==========================================

def get_room_dimensions_from_buffer(file_storage):
    """Saves temporary file to read USDZ dimensions."""
    temp_path = "temp_room_scan.usdz"
    file_storage.save(temp_path)
    try:
        stage = Usd.Stage.Open(temp_path)
        if not stage: return None
        meters_per_unit = UsdGeom.GetStageMetersPerUnit(stage)
        bbox_cache = UsdGeom.BBoxCache(Usd.TimeCode.Default(), [UsdGeom.Tokens.default_])
        root = stage.GetPseudoRoot()
        bbox = bbox_cache.ComputeWorldBound(root)
        size = bbox.GetRange().GetSize()
        
        # Returns Width, Height, Depth in CM (IKEA standard)
        return {
            "w": size[0] * meters_per_unit * 100,
            "h": size[1] * meters_per_unit * 100,
            "d": size[2] * meters_per_unit * 100
        }
    finally:
        if os.path.exists(temp_path): os.remove(temp_path)

def ask_gemini_for_furniture(dims, room_type):
    """
    Uses Gemini 2.5 Flash to suggest furniture.
    Note: The new SDK supports 'response_mime_type' for native JSON output.
    """
    print(f"🤖 Consulting {MODEL_ID} for {room_type}...")
    
    prompt = f"""
    A user scanned a {room_type} with dimensions (cm): 
    Width: {dims['w']:.1f}, Height: {dims['h']:.1f}, Depth: {dims['d']:.1f}.
    
    Suggest ONE essential IKEA furniture piece that fits logically in this space.
    Return a JSON object with:
    - furniture_query: Specific IKEA product name (e.g., 'KALLAX shelf')
    - target_width: optimal width in cm
    - target_depth: optimal depth in cm
    - target_height: optimal height in cm
    - reasoning: why this fits these specific dimensions
    """

    try:
        # The new SDK allows forcing JSON output via config
        response = client.models.generate_content(
            model=MODEL_ID,
            contents=prompt,
            config=types.GenerateContentConfig(
                response_mime_type='application/json',
            ),
        )
        
        # response.text is now guaranteed to be clean JSON
        return json.loads(response.text)

    except Exception as e:
        print(f"❌ Gemini 2.5 Error: {e}")
        # Reliable fallback
        return {
            "furniture_query": "IKEA BILLY Bookcase",
            "target_width": 80.0,
            "target_depth": 28.0,
            "target_height": 202.0,
            "reasoning": "Standard fallback due to API error."
            }

# ==========================================
# 3. CORE PROCESSING (Original Logic Kept)
# ==========================================

def enhance_image_for_3d(pil_img):
    img = pil_img.filter(ImageFilter.SMOOTH_MORE)
    img = ImageEnhance.Sharpness(img).enhance(2.0)
    img = ImageEnhance.Contrast(img).enhance(1.2)
    return img

@dataclass
class ScrapedProduct:
    name: str
    image_url: str
    link: str
    scraped_width: Optional[float] = None
    scraped_depth: Optional[float] = None
    scraped_height: Optional[float] = None
    distance_score: float = float('inf')

def clean_url(url: str) -> str:
    try:
        parsed = urlparse(url)
        return urlunparse((parsed.scheme, parsed.netloc, parsed.path, '', '', ''))
    except: return url

def enforce_high_res_url(url: str) -> str:
    if not url: return ""
    return url.split("?")[0] if "?" in url else url

def calculate_distance(tw, td, th, aw, ad, ah):
    if None in [aw, ad, ah]: return float('inf')
    return ((tw-aw)**2 + (td-ad)**2 + (th-ah)**2)**0.5

def create_driver():
    if not HAS_SELENIUM: return None
    opts = ChromeOptions()
    opts.add_argument("--headless=new")
    opts.add_argument("--no-sandbox")
    opts.add_argument("--disable-dev-shm-usage")
    service = ChromeService(ChromeDriverManager().install())
    driver = webdriver.Chrome(service=service, options=opts)
    return driver

def extract_dimensions_from_text(text: str) -> dict:
    dims = {"width": None, "depth": None, "height": None}
    patterns = [r'(\d+(?:\.\d+)?)\s*(?:"|cm|in)?\s*[xX×]\s*(\d+(?:\.\d+)?)\s*(?:"|cm|in)?\s*[xX×]\s*(\d+(?:\.\d+)?)\s*(?:"|cm|in)?']
    triplet = re.search(patterns[0], text)
    if triplet:
        dims["width"], dims["depth"], dims["height"] = float(triplet.group(1)), float(triplet.group(2)), float(triplet.group(3))
    return dims

def fetch_search_results(query, max_items):
    driver = create_driver()
    if not driver: return []
    links = []
    try:
        url = f"https://www.ikea.com/us/en/search/?q={quote_plus(query)}"
        driver.get(url)
        time.sleep(2)
        soup = BeautifulSoup(driver.page_source, "html.parser")
        seen = set()
        for a in soup.find_all('a', href=True):
            href = a['href']
            if "/p/" in href:
                if href.startswith('/'): href = "https://www.ikea.com" + href
                clean = clean_url(href)
                if clean not in seen:
                    seen.add(clean)
                    links.append({"url": clean, "title": a.get_text(strip=True)})
                    if len(links) >= max_items: break
    finally:
        driver.quit()
    return links

def fetch_product_details(link_data, tw, td, th):
    driver = create_driver()
    if not driver: return None
    try:
        driver.get(link_data["url"])
        time.sleep(1)
        soup = BeautifulSoup(driver.page_source, "html.parser")
        og_img = soup.find("meta", property="og:image")
        image_url = enforce_high_res_url(og_img["content"]) if og_img else ""
        dims = extract_dimensions_from_text(driver.page_source)
        dist = calculate_distance(tw, td, th, dims["width"], dims["depth"], dims["height"])
        return ScrapedProduct(name=link_data["title"], image_url=image_url, link=link_data["url"],
                              scraped_width=dims["width"], scraped_depth=dims["depth"], scraped_height=dims["height"],
                              distance_score=dist)
    finally:
        driver.quit()

# ==========================================
# 4. NEW INTEGRATED ROUTE
# ==========================================

@app.route('/roomscan', methods=['POST'])
def roomscan_to_furniture():
    """
    Accepts a USDZ file and room_type.
    Uses Gemini to pick furniture, Scraper to find it, and SF3D to build it.
    """
    if 'file' not in request.files:
        return jsonify({"error": "No USDZ file provided"}), 400
    
    room_type = request.form.get('room_type', 'living room')
    usdz_file = request.files['file']
    
    # 1. Get Dimensions from USDZ
    print("📏 Extracting dimensions...")
    room_dims = get_room_dimensions_from_buffer(usdz_file)
    if not room_dims:
        return jsonify({"error": "Failed to parse USDZ dimensions"}), 400

    # 2. Ask Gemini what to put there
    print(f"🤖 Consulting Gemini for {room_type}...")
    suggestion = ask_gemini_for_furniture(room_dims, room_type)
    query = suggestion['furniture_query']
    print(f"💡 Gemini suggests: {query}")

    # 3. Search IKEA for best match
    links = fetch_search_results(query, 3)
    if not links:
        return jsonify({"error": f"No products found for {query}"}), 404
    
    best_product = None
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
        futures = [executor.submit(fetch_product_details, l, suggestion['target_width'], 
                                   suggestion['target_depth'], suggestion['target_height']) for l in links]
        results = [f.result() for f in concurrent.futures.as_completed(futures) if f.result()]
        if results:
            best_product = min(results, key=lambda p: p.distance_score)

    if not best_product:
        return jsonify({"error": "Product details could not be parsed"}), 404

    # 4. Process and Generate 3D
    print(f"🎨 Generating 3D Model: {best_product.name}")
    resp = requests.get(best_product.image_url, stream=True)
    img = Image.open(io.BytesIO(resp.content))
    
    # Reuse your existing processing logic
    return process_and_respond(img, percentage=10, format='usdz')

# ==========================================
# 5. MODIFIED RESPONSE LOGIC
# ==========================================

def process_and_respond(pil_img, percentage, format='glb'):
    start_time = time.time()
    # Create a temporary directory for the conversion process
    temp_dir = tempfile.mkdtemp()
    
    try:
        img = pil_img.convert("RGBA")
        img = remove_background(img, rembg_session)
        img = resize_foreground(img, 0.85)
        img = enhance_image_for_3d(img) 
        
        with torch.no_grad():
            with torch.autocast(device_type=device, dtype=torch.bfloat16) if "cuda" in device else nullcontext():
                result = model.run_image([img], bake_resolution=1024, remesh="none", vertex_count=-1)
                mesh = result[0] if isinstance(result, (list, tuple)) else result
        
        # 1. Export initial GLB from model
        glb_path = os.path.join(temp_dir, "model.glb")
        mesh.export(glb_path, file_type='glb')
        
        # 2. Load into Trimesh for centering & leveling
        tm = trimesh.load(glb_path, file_type='glb', force='mesh')
        tm.apply_translation([-tm.centroid[0], 0, -tm.centroid[2]])
        tm = geometry_auto_level(tm, bottom_percent=percentage)
        
        min_y = tm.bounds[0][1]
        tm.apply_translation([0, -min_y, 0])
        
        # Save the leveled GLB
        tm.export(glb_path, file_type='glb')
        
        if format == 'usdz':
            usdz_path = os.path.join(temp_dir, "final_output.usdz")
            
            # --- PXR CONVERSION LOGIC ---
            # We open the GLB as a Stage and export it as a USDZ package
            stage = Usd.Stage.Open(glb_path)
            if not stage:
                raise ValueError("USD: Could not open GLB stage for conversion.")
            
            # Export as USDZ
            stage.Export(usdz_path)
            
            with open(usdz_path, 'rb') as f:
                data = io.BytesIO(f.read())
            
            mimetype = 'model/vnd.usd+zip'
            download_name = 'furniture_suggested.usdz'
        else:
            with open(glb_path, 'rb') as f:
                data = io.BytesIO(f.read())
            mimetype = 'model/gltf-binary'
            download_name = 'model.glb'

        data.seek(0)
        print(f"🎉 Pipeline Complete in {time.time() - start_time:.2f}s")
        return send_file(data, mimetype=mimetype, as_attachment=True, download_name=download_name)
        
    except Exception as e:
        print("❌ CRITICAL ERROR:")
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500
    finally:
        # Cleanup temp files
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)

# Original endpoints preserved for debugging
@app.route('/health', methods=['GET'])
def health(): return jsonify({"status": "online"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
