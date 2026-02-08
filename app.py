import os
import sys

# --- CRITICAL CONFIGURATION ---
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
import aspose.threed as a3d
from concurrent.futures import ThreadPoolExecutor, as_completed

from flask import Flask, request, jsonify, Response
from flask_cors import CORS
from PIL import Image
from pxr import Usd, UsdGeom, Sdf
from bs4 import BeautifulSoup
from urllib.parse import quote_plus

# --- TRELLIS IMPORTS ---
if os.getcwd() not in sys.path:
    sys.path.append(os.getcwd())

try:
    from trellis.pipelines import TrellisImageTo3DPipeline
    from trellis.utils import postprocessing_utils
except ImportError:
    print("❌ Error: Could not import 'trellis'. Make sure you are in the correct directory.")
    sys.exit(1)

from google import genai
from google.genai import types

# ==========================================
# 1. SETUP & CLIENTS
# ==========================================
API_KEY = ""
client = genai.Client(api_key=API_KEY)
MODEL_ID = "gemini-2.5-flash"

app = Flask(__name__)
CORS(app)

model_store = {}
rembg_session = rembg.new_session()

# Persistent session for high-speed scraping
http_session = requests.Session()
http_session.headers.update({
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
})

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
# 2. CONVERSION & GROUNDING (ASPOSE)
# ==========================================

def process_and_convert_to_usdz(glb_path, output_usdz_path):
    """
    Centers the model, grounds it (Feet at Y=0), and converts to high-fidelity USDZ.
    """
    try:
        scene = a3d.Scene.from_file(glb_path)
        bbox = scene.root_node.get_bounding_box()
        
        if bbox:
            min_y = bbox.minimum.y
            center_x = (bbox.minimum.x + bbox.maximum.x) / 2
            center_z = (bbox.minimum.z + bbox.maximum.z) / 2
            
            # Ground and Center the model
            scene.root_node.transform.translation = a3d.utilities.Vector3(-center_x, -min_y, -center_z)
            
            bounds_m = (
                bbox.maximum.x - bbox.minimum.x,
                bbox.maximum.y - bbox.minimum.y,
                bbox.maximum.z - bbox.minimum.z
            )
        else:
            bounds_m = (1.0, 1.0, 1.0)

        save_options = a3d.formats.UsdSaveOptions(a3d.FileFormat.USDZ)
        scene.save(output_usdz_path, save_options)
        
        return True, bounds_m
    except Exception as e:
        print(f"❌ Aspose Conversion Failed: {e}")
        return False, (1.0, 1.0, 1.0)

# ==========================================
# 3. HIGH-SPEED SCRAPING (IKEA API)
# ==========================================

def clean_dimension_value(val_str):
    if not val_str: return 0.8
    try:
        match = re.search(r'([\d\.]+)', str(val_str))
        if not match: return 0.8
        return float(match.group(1)) * 0.0254 
    except:
        return 0.8

def fetch_search_results_fast(query):
    try:
        api_url = f"https://sik.search.blue.cdtapps.com/us/en/search-result-page?q={quote_plus(query)}&size=1"
        resp = http_session.get(api_url, timeout=5)
        if resp.status_code == 200:
            items = resp.json().get('searchResultPage', {}).get('products', {}).get('main', {}).get('items', [])
            if items:
                p = items[0].get('product', {})
                return [{"url": p.get('pipUrl'), "title": p.get('name')}]
    except: pass
    return []

def fetch_product_details_fast(link_data):
    try:
        resp = http_session.get(link_data['url'], timeout=5)
        soup = BeautifulSoup(resp.content, "html.parser")
        tag = soup.find('script', {'id': 'pip-range-json-ld'})
        if not tag: return None
        data = json.loads(tag.string)
        
        return {
            "name": data.get("name"),
            "image_url": data.get("image", [{}])[0].get("contentUrl"),
            "link": link_data["url"],
            "price": float(data.get("offers", {}).get("price", 99)),
            "width_m": clean_dimension_value(data.get("width")),
            "height_m": clean_dimension_value(data.get("height")),
            "depth_m": clean_dimension_value(data.get("depth"))
        }
    except: return None

# ==========================================
# 4. INTELLIGENT ROOM ANALYSIS
# ==========================================

def get_room_dimensions_from_buffer(file_storage):
    temp_path = "temp_scan.usdz"
    file_storage.save(temp_path)
    try:
        stage = Usd.Stage.Open(temp_path)
        if not stage: return None
        
        m_per_u = UsdGeom.GetStageMetersPerUnit(stage)
        up_axis = UsdGeom.GetStageUpAxis(stage)
        
        bboxes = []
        for prim in stage.Traverse():
            if prim.IsA(UsdGeom.Mesh):
                bound = UsdGeom.BBoxCache(Usd.TimeCode.Default(), [UsdGeom.Tokens.default_]).ComputeWorldBound(prim)
                bboxes.append(bound.GetRange())

        if not bboxes:
            bound = UsdGeom.BBoxCache(Usd.TimeCode.Default(), [UsdGeom.Tokens.default_]).ComputeWorldBound(stage.GetPseudoRoot())
            full_range = bound.GetRange()
        else:
            full_range = bboxes[0]
            for b in bboxes[1:]: full_range.UnionWith(b)

        size = full_range.GetSize()
        min_p = full_range.GetMin()
        
        x_cm, y_cm, z_cm = size[0]*m_per_u*100, size[1]*m_per_u*100, size[2]*m_per_u*100
        dims_list = sorted([x_cm, y_cm, z_cm], reverse=True)
        floor_y = (min_p[2] if up_axis == 'Z' else min_p[1]) * m_per_u
        
        return {"w": dims_list[0], "d": dims_list[1], "h": dims_list[2], "floor_y": floor_y}
    finally:
        if os.path.exists(temp_path): os.remove(temp_path)

def ask_gemini_for_furniture(dims, room_type):
    print(f"🤖 AI Stage: Designing '{room_type}' ({dims['w']:.0f}x{dims['d']:.0f}cm)...")
    prompt = f"""
    You are an expert Interior Designer. 
    Room: '{room_type}' (W:{dims['w']:.0f}cm, D:{dims['d']:.0f}cm).
    Suggest 2-5 cohesive high-end furniture items. Rules: No brand names. 
    Use visual descriptive queries like 'Modern charcoal velvet sofa'.
    Return JSON only: {{ "items": [ {{ "furniture_query": "search query" }} ] }}
    """
    try:
        response = client.models.generate_content(
            model=MODEL_ID, contents=prompt, 
            config=types.GenerateContentConfig(response_mime_type='application/json')
        )
        return json.loads(response.text).get("items", [])
    except Exception as e:
        print(f"   ⚠️ AI Error: {e}")
        return [{"furniture_query": "Modern Armchair"}]

# ==========================================
# 5. CORE 3D PIPELINE
# ==========================================

def run_pipeline_return_glb(pil_img):
    """DEBUG: Raw GLB output."""
    temp_dir = tempfile.mkdtemp()
    try:
        img = rembg.remove(pil_img.convert("RGBA"), session=rembg_session)
        outputs = pipeline.run(img, seed=1, formats=["gaussian", "mesh"], preprocess_image=False)
        glb_path = os.path.join(temp_dir, "raw.glb")
        glb_obj = postprocessing_utils.to_glb(outputs['gaussian'][0], outputs['mesh'][0], simplify=0.95, texture_size=1024, verbose=False)
        glb_obj.export(glb_path)
        with open(glb_path, 'rb') as f: return f.read()
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

def run_pipeline_return_usdz(pil_img):
    """APP: Grounded USDZ output."""
    temp_dir = tempfile.mkdtemp()
    try:
        img = rembg.remove(pil_img.convert("RGBA"), session=rembg_session)
        outputs = pipeline.run(img, seed=1, formats=["gaussian", "mesh"], preprocess_image=False)
        raw_glb = os.path.join(temp_dir, "raw.glb")
        glb_obj = postprocessing_utils.to_glb(outputs['gaussian'][0], outputs['mesh'][0], simplify=0.95, texture_size=1024, verbose=False)
        glb_obj.export(raw_glb)
        
        usdz_path = os.path.join(temp_dir, "output.usdz")
        success, bounds_m = process_and_convert_to_usdz(raw_glb, usdz_path)
        if not success: raise Exception("Aspose failed")
        
        with open(usdz_path, 'rb') as f: return f.read(), bounds_m
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

def process_single_furniture_item(item):
    query = item.get("furniture_query", "Furniture")
    links = fetch_search_results_fast(query)
    if not links: return None
    return fetch_product_details_fast(links[0])

# ==========================================
# 6. ROUTES
# ==========================================

@app.route('/dream', methods=['POST'])
def dream():
    print("\n💤 DREAM REQUEST RECEIVED (RAW GLB)")
    query = request.form.get('query')
    if not query: return jsonify({"error": "No query"}), 400

    links = fetch_search_results_fast(query)
    if not links: return "Not found", 404
    prod = fetch_product_details_fast(links[0])
    
    print(f"   📸 Found: {prod['name']}")
    print(f"   📏 Dims (m): W:{prod['width_m']:.2f}, H:{prod['height_m']:.2f}, D:{prod['depth_m']:.2f}, Price: ${prod['price']}")
    
    img = Image.open(io.BytesIO(http_session.get(prod['image_url']).content))
    glb_data = run_pipeline_return_glb(img)
    
    return Response(glb_data, mimetype="model/gltf-binary", headers={"Content-Disposition": f"attachment; filename={query}.glb"})

@app.route('/roomscan', methods=['POST'])
def roomscan():
    if 'file' not in request.files: return "No file", 400
    room_dims = get_room_dimensions_from_buffer(request.files['file'])
    if not room_dims: return "Bad Scan", 400
    floor_y = room_dims['floor_y']

    suggestions = ask_gemini_for_furniture(room_dims, request.form.get('room_type', 'room'))
    
    print("   🚀 Scraping items in parallel...")
    scraped_data = []
    with ThreadPoolExecutor(max_workers=5) as executor:
        futures = {executor.submit(process_single_furniture_item, item): i for i, item in enumerate(suggestions[:5])}
        for f in as_completed(futures):
            res = f.result()
            if res: scraped_data.append({"prod": res, "idx": futures[f]})

    furniture_list = []
    scraped_data.sort(key=lambda x: x['idx'])
    for item in scraped_data:
        try:
            prod = item['prod']
            img = Image.open(io.BytesIO(http_session.get(prod['image_url']).content))
            data, bounds_m = run_pipeline_return_usdz(img)
            mid = str(uuid.uuid4())
            model_store[mid] = data
            sx, sy, sz = prod['width_m']/bounds_m[0], prod['height_m']/bounds_m[1], prod['depth_m']/bounds_m[2]
            px = (item['idx'] - (len(scraped_data)-1)/2) * 1.2
            
            furniture_list.append({
                "furniture_id": str(uuid.uuid4()), "usdz_url": f"/roomscan/model/{mid}",
                "position": {"x": px, "y": floor_y, "z": 0}, "scale": {"x": sx, "y": sy, "z": sz},
                "page_link": prod['link'], "price": str(int(prod['price'])), "description": prod['name'],
                "dimensions": f"{prod['width_m']:.2f}x{prod['height_m']:.2f}x{prod['depth_m']:.2f}m"
            })
        except: pass

    response_payload = {
        "scan_id": str(uuid.uuid4()),
        "plans": [{"plan_id": str(uuid.uuid4()), "furniture": furniture_list, "total_items": len(furniture_list)}],
        "total_plans": 1
    }
    print("\n📦 FINAL ROOMSCAN RESPONSE:")
    print(json.dumps(response_payload, indent=2))
    return jsonify(response_payload)

@app.route('/request', methods=['POST'])
def handle_request():
    """Returns exact same JSON structure as roomscan to prevent decoding errors."""
    prompt = request.form.get('prompt')
    if not prompt: return jsonify({"error": "No prompt"}), 400
    
    print(f"\n🚀 CUSTOM REQUEST: '{prompt}'")
    links = fetch_search_results_fast(prompt)
    if not links: return "Not found", 404
    prod = fetch_product_details_fast(links[0])
    
    img = Image.open(io.BytesIO(http_session.get(prod['image_url']).content))
    data, bounds_m = run_pipeline_return_usdz(img)
    mid = str(uuid.uuid4())
    model_store[mid] = data
    
    sx, sy, sz = prod['width_m']/bounds_m[0], prod['height_m']/bounds_m[1], prod['depth_m']/bounds_m[2]
    
    furniture_list = [{
        "furniture_id": str(uuid.uuid4()), "usdz_url": f"/roomscan/model/{mid}",
        "position": {"x": 0, "y": 0, "z": 0}, "scale": {"x": sx, "y": sy, "z": sz},
        "page_link": prod['link'], "price": str(int(prod['price'])), "description": prod['name'],
        "dimensions": f"{prod['width_m']:.2f}x{prod['height_m']:.2f}x{prod['depth_m']:.2f}m"
    }]
    
    response_payload = {
        "scan_id": str(uuid.uuid4()),
        "plans": [{"plan_id": str(uuid.uuid4()), "furniture": furniture_list, "total_items": 1}],
        "total_plans": 1
    }
    print("\n📦 FINAL REQUEST RESPONSE:")
    print(json.dumps(response_payload, indent=2))
    return jsonify(response_payload)

@app.route('/roomscan/model/<mid>', methods=['GET'])
def get_model(mid):
    if mid not in model_store: return "404", 404
    return Response(model_store.pop(mid), mimetype="model/vnd.usdz+zip")

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
