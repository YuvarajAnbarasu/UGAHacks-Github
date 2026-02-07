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
from dataclasses import dataclass
from typing import Optional
from urllib.parse import quote_plus, urlparse, urlunparse
from flask import Flask, request, send_file, jsonify
from flask_cors import CORS
from sf3d.system import SF3D
from sf3d.utils import remove_background, resize_foreground
from PIL import Image
from contextlib import nullcontext

# --- SELENIUM IMPORTS ---
try:
    from selenium import webdriver
    from selenium.webdriver.chrome.options import Options as ChromeOptions
    from selenium.webdriver.chrome.service import Service as ChromeService
    from webdriver_manager.chrome import ChromeDriverManager
    from bs4 import BeautifulSoup
    HAS_SELENIUM = True
except ImportError:
    print("⚠️ WARNING: Selenium/BS4 not found. /dream endpoint will not work.")
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
print("✅ SERVER READY! Waiting for requests...")


# ==========================================
# 2. SCRAPER LOGIC (IKEA)
# ==========================================

MAX_PARALLEL_BROWSERS = 3
SEARCH_POOL_SIZE = 4  # Check top 4 items for speed

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
    except:
        return url

def calculate_distance(target_w, target_d, target_h, actual_w, actual_d, actual_h):
    if actual_w is None or actual_d is None or actual_h is None:
        return float('inf')
    w_diff = (target_w - actual_w) ** 2
    d_diff = (target_d - actual_d) ** 2
    h_diff = (target_h - actual_h) ** 2
    return (w_diff + d_diff + h_diff) ** 0.5

def create_driver():
    """Creates a stealthy Chrome driver to bypass simple bot detection."""
    if not HAS_SELENIUM: return None
    opts = ChromeOptions()
    
    # Headless but stealthy
    opts.add_argument("--headless=new")
    opts.add_argument("--no-sandbox")
    opts.add_argument("--disable-dev-shm-usage")
    opts.add_argument("--disable-gpu")
    opts.add_argument("--window-size=1920,1080")
    opts.page_load_strategy = 'eager'
    
    # ANTI-BOT: Fake User Agent & Disable Automation Flags
    user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    opts.add_argument(f'user-agent={user_agent}')
    opts.add_argument("--disable-blink-features=AutomationControlled")
    opts.add_experimental_option("excludeSwitches", ["enable-automation"])
    opts.add_experimental_option('useAutomationExtension', False)
    
    try:
        service = ChromeService(ChromeDriverManager().install())
        driver = webdriver.Chrome(service=service, options=opts)
        
        # Extra layer: Remove navigator.webdriver property
        driver.execute_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")
        return driver
    except Exception as e:
        print(f"Driver Error: {e}")
        return None

def extract_dimensions_from_text(text: str) -> dict:
    dims = {"width": None, "depth": None, "height": None}
    if not text: return dims
    
    patterns = [
        r'(\d+(?:\.\d+)?)\s*(?:"|cm|in)?\s*[xX×]\s*(\d+(?:\.\d+)?)\s*(?:"|cm|in)?\s*[xX×]\s*(\d+(?:\.\d+)?)\s*(?:"|cm|in)?',
        r'Width[:\s]+(\d+(?:\.\d+)?)',
        r'Depth[:\s]+(\d+(?:\.\d+)?)',
        r'Height[:\s]+(\d+(?:\.\d+)?)',
    ]
    
    triplet = re.search(patterns[0], text)
    if triplet:
        dims["width"], dims["depth"], dims["height"] = float(triplet.group(1)), float(triplet.group(2)), float(triplet.group(3))
        return dims
    
    w_match = re.search(patterns[1], text, re.IGNORECASE)
    d_match = re.search(patterns[2], text, re.IGNORECASE)
    h_match = re.search(patterns[3], text, re.IGNORECASE)
    
    if w_match: dims["width"] = float(w_match.group(1))
    if d_match: dims["depth"] = float(d_match.group(1))
    if h_match: dims["height"] = float(h_match.group(1))
    return dims

def fetch_search_results(query, max_items):
    driver = create_driver()
    if not driver: return []
    links = []
    try:
        url = f"https://www.ikea.com/us/en/search/?q={quote_plus(query)}"
        print(f"   🕷️ Scraping: {url}")
        driver.get(url)
        time.sleep(2.5) # Wait for JS to load
        
        soup = BeautifulSoup(driver.page_source, "html.parser")
        
        # Check for bot block
        if "Access Denied" in (soup.title.string if soup.title else ""):
            print("   ⛔ Blocked by IKEA.")
            return []
            
        seen = set()
        count = 0
        for a in soup.find_all('a', href=True):
            href = a['href']
            if "/p/" in href and "ikea.com" in href:
                if href.startswith('/'): href = "https://www.ikea.com" + href
                clean = clean_url(href)
                
                if clean in seen: continue
                seen.add(clean)
                
                title = a.get_text(strip=True)
                if len(title) > 3:
                    links.append({"url": clean, "title": title})
                    count += 1
                    if count >= max_items: break
        
        print(f"   ✅ Found {len(links)} potential matches.")
                    
    except Exception as e:
        print(f"Search Error: {e}")
    finally:
        driver.quit()
    return links

def fetch_product_details(link_data, tw, td, th):
    driver = create_driver()
    if not driver: return None
    try:
        driver.get(link_data["url"])
        time.sleep(0.5)
        html = driver.page_source
        
        image_url = ""
        soup = BeautifulSoup(html, "html.parser")
        og_img = soup.find("meta", property="og:image")
        if og_img: image_url = og_img["content"]
        
        dims = extract_dimensions_from_text(html)
        dist = calculate_distance(tw, td, th, dims["width"], dims["depth"], dims["height"])
        
        return ScrapedProduct(
            name=link_data["title"],
            image_url=image_url,
            link=link_data["url"],
            scraped_width=dims["width"],
            scraped_depth=dims["depth"],
            scraped_height=dims["height"],
            distance_score=dist
        )
    except:
        return None
    finally:
        driver.quit()

def find_best_match(query, w, d, h):
    print(f"🔎 searching IKEA for: '{query}'...")
    links = fetch_search_results(query, SEARCH_POOL_SIZE)
    if not links: return None
    
    products = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_PARALLEL_BROWSERS) as executor:
        futures = [executor.submit(fetch_product_details, l, w, d, h) for l in links]
        for f in concurrent.futures.as_completed(futures):
            p = f.result()
            if p and p.scraped_width: products.append(p)
            
    if not products: return None
    return min(products, key=lambda p: p.distance_score)

# ==========================================
# 3. 3D PROCESSING LOGIC
# ==========================================

def rotation_matrix_from_vectors(vec1, vec2):
    a, b = (vec1 / np.linalg.norm(vec1)), (vec2 / np.linalg.norm(vec2))
    v = np.cross(a, b)
    s = np.linalg.norm(v)
    if s == 0: return np.eye(4)
    kmat = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    rotation_matrix = np.eye(3) + kmat + kmat.dot(kmat) * ((1 - np.dot(a, b)) / (s ** 2))
    M = np.eye(4)
    M[:3, :3] = rotation_matrix
    return M

def geometry_auto_level(mesh, bottom_percent=10.0):
    try:
        vertices = mesh.vertices
        min_y, max_y = np.min(vertices[:, 1]), np.max(vertices[:, 1])
        
        decimal = float(bottom_percent) / 100.0
        decimal = max(min(decimal, 0.5), 0.01)
        thresh = min_y + (max_y - min_y) * decimal
        
        feet_points = vertices[vertices[:, 1] < thresh]
        if len(feet_points) < 10: return mesh

        centroid = np.mean(feet_points, axis=0)
        u, s, vh = np.linalg.svd((feet_points - centroid).T)
        normal = u[:, -1]
        if normal[1] < 0: normal = -normal
        
        up = np.array([0, 1, 0])
        angle = np.degrees(np.arccos(max(min(np.dot(normal, up), 1.0), -1.0)))
        
        print(f"   📐 Detected Tilt: {angle:.2f}°")
        
        if 0.5 < angle < 20.0:
            R = rotation_matrix_from_vectors(normal, up)
            mesh.apply_transform(R)
            print("   ✅ Mesh leveled.")
            
    except Exception as e:
        print(f"   ⚠️ Leveling failed: {e}")
    return mesh

# ==========================================
# 4. FLASK ROUTES
# ==========================================

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "online", "gpu": torch.cuda.get_device_name(0)})

@app.route('/generate', methods=['POST'])
def generate_from_file():
    """Upload an image file directly"""
    if 'image' not in request.files:
        return jsonify({"error": "No image provided"}), 400
    
    file = request.files['image']
    percent = request.form.get('percentage', 10)
    return process_and_respond(Image.open(file.stream), percent)

@app.route('/dream', methods=['POST'])
def generate_from_scraper():
    """Text + Dimensions -> IKEA Match -> 3D Model"""
    if not HAS_SELENIUM:
        return jsonify({"error": "Server missing scraping tools"}), 500
        
    data = request.form
    query = data.get('query', '')
    
    try:
        w = float(data.get('width', 0))
        d = float(data.get('depth', 0))
        h = float(data.get('height', 0))
    except:
        return jsonify({"error": "Invalid dimensions"}), 400
        
    if not query:
        return jsonify({"error": "Query required"}), 400
        
    # 1. Scrape
    print(f"🚀 Processing Dream Request: {query}")
    best_match = find_best_match(query, w, d, h)
    
    if not best_match:
        return jsonify({"error": "No matching products found on IKEA"}), 404
        
    print(f"✅ Matched: {best_match.name} (Dist: {best_match.distance_score:.2f})")
    
    # 2. Download Image
    try:
        # User-Agent header for download (just in case image CDN checks too)
        headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
        resp = requests.get(best_match.image_url, headers=headers, stream=True)
        resp.raise_for_status()
        img = Image.open(io.BytesIO(resp.content))
    except Exception as e:
        return jsonify({"error": f"Failed to download image: {e}"}), 500
        
    # 3. Generate 3D
    response = process_and_respond(img, percentage=10)
    
    # 4. Attach Metadata for Frontend
    response.headers["X-Scraped-Name"] = best_match.name
    response.headers["X-Scraped-Link"] = best_match.link
    return response

def process_and_respond(pil_img, percentage):
    """Shared 3D pipeline"""
    start_time = time.time()
    try:
        img = pil_img.convert("RGBA")
        img = remove_background(img, rembg_session)
        img = resize_foreground(img, 0.85)
        
        with torch.no_grad():
            with torch.autocast(device_type=device, dtype=torch.bfloat16) if "cuda" in device else nullcontext():
                result = model.run_image([img], bake_resolution=1024, remesh="none", vertex_count=-1)
                mesh = result[0] if isinstance(result, (list, tuple)) else result
        
        # Safe Export (Centering + Leveling)
        buf = io.BytesIO()
        mesh.export(buf, file_type='glb')
        buf.seek(0)
        
        tm = trimesh.load(buf, file_type='glb', force='mesh')
        
        # 1. Center
        center = tm.centroid
        tm.apply_translation([-center[0], 0, -center[2]])
        
        # 2. Level (Bottom 10%)
        tm = geometry_auto_level(tm, bottom_percent=percentage)
        
        # 3. Floor
        min_y = tm.bounds[0][1]
        tm.apply_translation([0, -min_y, 0])
        
        final_buf = io.BytesIO()
        tm.export(final_buf, file_type='glb')
        final_buf.seek(0)
        
        print(f"🎉 Generated in {time.time() - start_time:.2f}s")
        return send_file(final_buf, mimetype='model/gltf-binary', as_attachment=True, download_name='model.glb')
        
    except Exception as e:
        print(f"❌ ERROR: {e}")
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
