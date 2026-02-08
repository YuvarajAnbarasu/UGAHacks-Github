import os
import sys

# --- CONFIGURATION ---
os.environ['ATTN_BACKEND'] = 'xformers'   
os.environ['SPCONV_ALGO'] = 'native'      

import torch
import io
import time
import re
import requests
import json
import uuid
import shutil
import traceback
import tempfile
import numpy as np
import rembg
import trimesh
import aspose.threed as a3d

from flask import Flask, request, jsonify, Response
from flask_cors import CORS
from PIL import Image, ImageEnhance, ImageFilter
from pxr import Usd, UsdGeom

# --- TRELLIS IMPORTS ---
if os.getcwd() not in sys.path:
    sys.path.append(os.getcwd())

try:
    from trellis.pipelines import TrellisImageTo3DPipeline
    from trellis.utils import postprocessing_utils
except ImportError:
    print("❌ Error: Could not import 'trellis'.")
    sys.exit(1)

from google import genai
from google.genai import types

# ==========================================
# 1. SETUP
# ==========================================
API_KEY = "AIzaSyD5eKao6gTHNddQcTgd0AvEYWkxJQZU9Pg"
client = genai.Client(api_key=API_KEY)
MODEL_ID = "gemini-2.5-flash"

app = Flask(__name__)
CORS(app)

model_store = {}
rembg_session = rembg.new_session()

print("⏳ INITIALIZING: Loading TRELLIS Model...")
device = "cuda" if torch.cuda.is_available() else "cpu"
try:
    pipeline = TrellisImageTo3DPipeline.from_pretrained("Microsoft/TRELLIS-image-large")
    pipeline.to(device)
    print(f"✅ TRELLIS loaded on {device}")
except Exception as e:
    print(f"❌ CRITICAL ERROR: Model failed to load. {e}")
    exit(1)

# ==========================================
# 2. ASPOSE CONVERSION (GLB -> USDZ)
# ==========================================
def convert_glb_to_usdz_aspose(glb_path, output_usdz_path):
    try:
        scene = a3d.Scene.from_file(glb_path)
        scene.save(output_usdz_path, a3d.FileFormat.USDZ)
        return True
    except Exception as e:
        print(f"❌ Aspose Conversion Failed: {e}")
        return False

# ==========================================
# 3. HELPER FUNCTIONS
# ==========================================
def remove_background(image, session=None):
    return rembg.remove(image, session=session)

def resize_foreground(image, ratio):
    image = np.array(image)
    if image.shape[-1] != 4: return Image.fromarray(image)
    alpha = np.where(image[..., 3] > 0)
    if len(alpha[0]) == 0: return Image.fromarray(image)
    y1, y2, x1, x2 = np.min(alpha[0]), np.max(alpha[0]), np.min(alpha[1]), np.max(alpha[1])
    fg = image[y1:y2, x1:x2]
    size = max(fg.shape[0], fg.shape[1])
    ph0, pw0 = (size - fg.shape[0]) // 2, (size - fg.shape[1]) // 2
    ph1, pw1 = size - fg.shape[0] - ph0, size - fg.shape[1] - pw0
    new_image = np.pad(fg, ((ph0, ph1), (pw0, pw1), (0, 0)), mode="constant", constant_values=0)
    new_size = int(new_image.shape[0] / ratio)
    ph0, pw0 = (new_size - size) // 2, (new_size - size) // 2
    ph1, pw1 = new_size - size - ph0, new_size - size - pw0
    new_image = np.pad(new_image, ((ph0, ph1), (pw0, pw1), (0, 0)), mode="constant", constant_values=0)
    return Image.fromarray(new_image)

def get_room_dimensions_from_buffer(file_storage):
    temp_path = "temp_scan.usdz"
    file_storage.save(temp_path)
    try:
        stage = Usd.Stage.Open(temp_path)
        if not stage: return None
        m_per_u = UsdGeom.GetStageMetersPerUnit(stage)
        bbox_cache = UsdGeom.BBoxCache(Usd.TimeCode.Default(), [UsdGeom.Tokens.default_])
        root_prim = stage.GetPseudoRoot()
        size = bbox_cache.ComputeWorldBound(root_prim).GetRange().GetSize()
        
        dims = {
            "w": size[0] * m_per_u * 100,
            "h": size[1] * m_per_u * 100,
            "d": size[2] * m_per_u * 100
        }
        print(f"✅ Room Dimensions (cm): {dims}")
        return dims
    finally:
        if os.path.exists(temp_path): os.remove(temp_path)

def ask_gemini_for_furniture(dims, room_type):
    print(f"🤖 Design Stage: Analyzing room ({dims['w']:.0f}x{dims['d']:.0f} cm)...")
    
    prompt = f"""
    You are an expert Interior Designer.
    The user has scanned a '{room_type}' with dimensions: Width {dims['w']:.0f}cm, Depth {dims['d']:.0f}cm.
    
    Your Goal:
    Suggest a cohesive furniture arrangement that fits this specific space comfortably.
    - If the room is small, suggest fewer, compact items (2-3 items).
    - If the room is large, fill it appropriately (max 5 items).
    - Ensure the items match in style (e.g., Modern, Minimalist, Industrial).
    
    CRITICAL INSTRUCTIONS:
    1. Do NOT use brand names (No 'IKEA', 'West Elm', etc.).
    2. Use purely DESCRIPTIVE queries for the 'furniture_query' field (e.g., 'Modern beige fabric sofa', 'Walnut wood coffee table', 'Industrial metal floor lamp').
    3. Estimate realistic dimensions (cm) for each item.
    
    Return JSON only:
    {{ 
      "style": "Brief description of the chosen style",
      "items": [ 
        {{ "furniture_query": "Visual description for search", "target_width_cm": number, "target_depth_cm": number, "target_height_cm": number }}
      ]
    }}
    """
    try:
        response = client.models.generate_content(
            model=MODEL_ID, contents=prompt,
            config=types.GenerateContentConfig(response_mime_type='application/json')
        )
        data = json.loads(response.text)
        items = data.get("items", [])
        print(f"   💡 Gemini suggested {len(items)} items. Style: {data.get('style', 'Mixed')}")
        return items
    except Exception as e:
        print(f"   ⚠️ AI Error: {e}")
        return [{"furniture_query": "Modern Lounge Chair", "target_width_cm": 80, "target_depth_cm": 80, "target_height_cm": 80}]

# ==========================================
# 4. SCRAPER (Acts as Search Engine)
# ==========================================
try:
    from selenium import webdriver
    from selenium.webdriver.chrome.options import Options as ChromeOptions
    from selenium.webdriver.chrome.service import Service as ChromeService
    from webdriver_manager.chrome import ChromeDriverManager
    from bs4 import BeautifulSoup
    from urllib.parse import quote_plus
    HAS_SELENIUM = True
except ImportError:
    HAS_SELENIUM = False

def create_driver():
    if not HAS_SELENIUM: return None
    opts = ChromeOptions()
    opts.add_argument("--headless=new")
    opts.add_argument("--no-sandbox")
    return webdriver.Chrome(service=ChromeService(ChromeDriverManager().install()), options=opts)

def fetch_search_results(query, max_items=1):
    print(f"🔎 Searching for '{query}'...")
    driver = create_driver()
    if not driver: return []
    links = []
    try:
        driver.get(f"https://www.ikea.com/us/en/search/?q={quote_plus(query)}")
        time.sleep(2)
        soup = BeautifulSoup(driver.page_source, "html.parser")
        for a in soup.find_all('a', href=True):
            if "/p/" in a['href']:
                url = "https://www.ikea.com" + a['href'] if a['href'].startswith('/') else a['href']
                links.append({"url": url, "title": a.get_text(strip=True)})
                if len(links) >= max_items: break
    finally: driver.quit()
    return links

def fetch_product_details(link_data):
    driver = create_driver()
    if not driver: return None
    try:
        driver.get(link_data["url"])
        time.sleep(1)
        soup = BeautifulSoup(driver.page_source, "html.parser")
        og_img = soup.find("meta", property="og:image")
        image_url = og_img["content"].split("?")[0] if og_img else ""
        
        # Default dims if not found
        w, h, d = 80, 80, 80
        
        return {
            "name": link_data["title"], "image_url": image_url, "link": link_data["url"],
            "price": 99.0, "width_cm": w, "height_cm": h, "depth_cm": d 
        }
    finally: driver.quit()

# ==========================================
# 5. PIPELINE EXECUTION (WITH ASPOSE)
# ==========================================
def run_pipeline_return_bytes(pil_img, output_format='usdz'):
    print(f"🎨 Starting TRELLIS Reconstruction...")
    start_time = time.time()
    temp_dir = tempfile.mkdtemp()
    
    try:
        # Preprocess
        img = remove_background(pil_img.convert("RGBA"), rembg_session)
        img = resize_foreground(img, 0.85) 
        
        # Inference
        outputs = pipeline.run(img, seed=1, formats=["gaussian", "mesh"], preprocess_image=False)
        
        trellis_gaussian = outputs['gaussian'][0]
        trellis_mesh = outputs['mesh'][0]
        
        # Export GLB (This preserves the rich texture/color data from Trellis)
        glb_object = postprocessing_utils.to_glb(trellis_gaussian, trellis_mesh, simplify=0.95, texture_size=1024, verbose=False)
        raw_glb_path = os.path.join(temp_dir, "raw.glb")
        glb_object.export(raw_glb_path)

        # Load GLB into Trimesh just to get bounds and center it
        tm = trimesh.load(raw_glb_path, file_type='glb', force='mesh')
        
        # Center & Floor
        tm.apply_translation([-tm.centroid[0], 0, -tm.centroid[2]])
        min_y = tm.bounds[0][1]
        tm.apply_translation([0, -min_y, 0])
        print(f"   ⚓ Anchored mesh to floor")

        # Calculate Bounds
        bmin, bmax = tm.bounds[0], tm.bounds[1]
        bounds_m = (bmax[0]-bmin[0], bmax[1]-bmin[1], bmax[2]-bmin[2])

        # Save corrected GLB
        corrected_glb_path = os.path.join(temp_dir, "corrected.glb")
        tm.export(corrected_glb_path)

        if output_format == 'glb':
            with open(corrected_glb_path, 'rb') as f:
                data = f.read()
            mimetype = "model/gltf-binary"
        else:
            # Use Aspose to convert Corrected GLB -> USDZ
            usdz_path = os.path.join(temp_dir, "output.usdz")
            print("   🔄 Converting with Aspose.3D...")
            success = convert_glb_to_usdz_aspose(corrected_glb_path, usdz_path)
            if not success: raise Exception("Aspose conversion failed")
            with open(usdz_path, 'rb') as f:
                data = f.read()
            mimetype = "model/vnd.usd+zip"

        print(f"🎉 Done in {time.time() - start_time:.2f}s")
        return (data, mimetype, bounds_m)

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

# ==========================================
# 6. ROUTES
# ==========================================
@app.route('/dream', methods=['POST'])
def dream():
    query = request.form.get('query')
    if not query: return jsonify({"error": "No query"}), 400

    links = fetch_search_results(query, 1)
    if not links: return jsonify({"error": "Not found"}), 404
    product = fetch_product_details(links[0])
    
    try:
        img_resp = requests.get(product['image_url'], timeout=10)
        img = Image.open(io.BytesIO(img_resp.content))
        data, mime, _ = run_pipeline_return_bytes(img, output_format='usdz')
        return Response(data, mimetype=mime, headers={
            "Content-Disposition": f"attachment; filename={query}.usdz"
        })
    except Exception as e:
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500

@app.route('/roomscan', methods=['POST'])
def roomscan():
    if 'file' not in request.files: return jsonify({"error": "No file"}), 400
    
    # 1. Get Room Info
    room_dims = get_room_dimensions_from_buffer(request.files['file'])
    if not room_dims: return jsonify({"error": "Bad Scan"}), 400
    room_type = request.form.get('room_type', 'room')

    # 2. Get AI Suggestions (Dynamic Count & Style)
    suggestions = ask_gemini_for_furniture(room_dims, room_type)
    
    furniture_list = []
    
    # 3. Generate Items (Max 5)
    for i, item in enumerate(suggestions[:5]):
        query = item.get("furniture_query", "Chair")
        links = fetch_search_results(query, 1)
        if not links: continue
        
        prod = fetch_product_details(links[0])
        try:
            img = Image.open(io.BytesIO(requests.get(prod['image_url']).content))
            data, mime, bounds_m = run_pipeline_return_bytes(img, output_format='usdz')
            
            mid = str(uuid.uuid4())
            model_store[mid] = (data, mime)
            
            # Smart Scaling
            target_w = prod['width_cm'] if prod['width_cm'] != 80 else item.get("target_width_cm", 80)
            target_h = prod['height_cm'] if prod['height_cm'] != 80 else item.get("target_height_cm", 80)
            target_d = prod['depth_cm'] if prod['depth_cm'] != 80 else item.get("target_depth_cm", 80)
            
            bw, bh, bd = bounds_m
            sx = (target_w / 100.0) / bw if bw > 0.01 else 1.0
            sy = (target_h / 100.0) / bh if bh > 0.01 else 1.0
            sz = (target_d / 100.0) / bd if bd > 0.01 else 1.0
            
            px = (i - (len(suggestions)-1)/2) * 1.2 
            
            furniture_list.append({
                "furniture_id": str(uuid.uuid4()),
                "usdz_url": f"/roomscan/model/{mid}",
                "position": {"x": px, "y": 0, "z": 0}, 
                "scale": {"x": sx, "y": sy, "z": sz},
                "page_link": prod['link'],
                "price": str(prod['price']),
                "description": query
            })
            
        except Exception as e:
            print(f"Failed item {query}: {e}")
            continue

    response_payload = {
        "scan_id": str(uuid.uuid4()),
        "plans": [{"plan_id": str(uuid.uuid4()), "furniture": furniture_list, "total_items": len(furniture_list)}],
        "total_plans": 1
    }
    
    # --- LOG OUTPUT FOR DEBUGGING ---
    print("\n📦 FINAL JSON RESPONSE:")
    print(json.dumps(response_payload, indent=2))
    print("-----------------------\n")

    return jsonify(response_payload)

@app.route('/roomscan/model/<mid>', methods=['GET'])
def get_model(mid):
    if mid not in model_store: return jsonify({"error": "404"}), 404
    data, mime = model_store.pop(mid)
    return Response(data, mimetype=mime, headers={"Content-Disposition": "attachment; filename=model.usdz"})

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "online", "gpu": torch.cuda.get_device_name(0), "model": "TRELLIS"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
