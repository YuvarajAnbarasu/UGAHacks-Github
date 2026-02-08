import os
import sys

# --- CRITICAL CONFIGURATION: MUST BE AT THE VERY TOP ---
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
from flask import Flask, request, jsonify, Response
from flask_cors import CORS
from PIL import Image, ImageEnhance, ImageFilter
from pxr import Usd, UsdGeom, UsdShade, Sdf, UsdUtils

# --- TRELLIS IMPORTS ---
if os.getcwd() not in sys.path:
    sys.path.append(os.getcwd())

try:
    from trellis.pipelines import TrellisImageTo3DPipeline
    from trellis.utils import postprocessing_utils
except ImportError:
    print("❌ Error: Could not import 'trellis'. Make sure you are running this script from inside the TRELLIS folder.")
    sys.exit(1)

from google import genai
from google.genai import types

# ==========================================
# 1. CONFIGURATION & CLIENTS
# ==========================================
API_KEY = "AIzaSyD5eKao6gTHNddQcTgd0AvEYWkxJQZU9Pg"
client = genai.Client(api_key=API_KEY)
MODEL_ID = "gemini-2.5-flash"

app = Flask(__name__)
CORS(app)

model_store = {}
rembg_session = rembg.new_session()

# ==========================================
# 2. MODEL INITIALIZATION (TRELLIS)
# ==========================================
print("⏳ INITIALIZING: Loading TRELLIS Model...")
device = "cuda" if torch.cuda.is_available() else "cpu"

try:
    # Using the official Microsoft repository
    pipeline = TrellisImageTo3DPipeline.from_pretrained(
        "Microsoft/TRELLIS-image-large"
    )
    pipeline.to(device)
    print(f"✅ TRELLIS loaded on {device}")
except Exception as e:
    print(f"❌ CRITICAL ERROR: Model failed to load. {e}")
    traceback.print_exc()
    exit(1)

# ==========================================
# 3. GEOMETRY & UTILS
# ==========================================

def remove_background(image, session=None):
    return rembg.remove(image, session=session)

def resize_foreground(image, ratio):
    image = np.array(image)
    assert image.shape[-1] == 4
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

def enhance_image_for_3d(pil_img):
    img = pil_img.filter(ImageFilter.SMOOTH_MORE)
    img = ImageEnhance.Sharpness(img).enhance(1.5)
    img = ImageEnhance.Contrast(img).enhance(1.1)
    return img

# ==========================================
# 4. USDZ & GEMINI AI LOGIC
# ==========================================

def get_room_dimensions_from_buffer(file_storage):
    print("📏 Stage 1: Reading USDZ Dimensions...")
    temp_path = "temp_scan.usdz"
    file_storage.save(temp_path)
    try:
        stage = Usd.Stage.Open(temp_path)
        if not stage: return None
        m_per_u = UsdGeom.GetStageMetersPerUnit(stage)
        bbox_cache = UsdGeom.BBoxCache(Usd.TimeCode.Default(), [UsdGeom.Tokens.default_])
        size = bbox_cache.ComputeWorldBound(stage.GetPseudoRoot()).GetRange().GetSize()
        dims = {"w": size[0]*m_per_u*100, "h": size[1]*m_per_u*100, "d": size[2]*m_per_u*100}
        print(f"✅ Dimensions Found (cm): {dims}")
        return dims
    finally:
        if os.path.exists(temp_path): os.remove(temp_path)

def ask_gemini_for_furniture(dims, room_type, num_items=3):
    print(f"🤖 Stage 2: Prompting {MODEL_ID} for {num_items} items in {room_type}...")
    prompt = f"""
    A user scanned a {room_type} with dimensions (cm): W: {dims['w']:.1f}, H: {dims['h']:.1f}, D: {dims['d']:.1f}.
    Suggest exactly {num_items} IKEA furniture pieces that would fit and look good together.
    Return JSON only, no markdown:
    {{ "items": [
      {{ "furniture_query": "IKEA product name", "target_width_cm": number, "target_depth_cm": number, "target_height_cm": number }}
    ]}}
    """
    try:
        response = client.models.generate_content(
            model=MODEL_ID, contents=prompt,
            config=types.GenerateContentConfig(response_mime_type='application/json')
        )
        data = json.loads(response.text)
        return data.get("items", [])
    except Exception as e:
        print(f"❌ Gemini Error: {e}")
        return [{"furniture_query": "IKEA Chair", "target_width_cm": 50, "target_depth_cm": 50, "target_height_cm": 80}]

# ==========================================
# 5. SCRAPER LOGIC
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
    print(f"🔎 Stage 3: Searching IKEA for '{query}'...")
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
    print(f"📸 Stage 4: Fetching product details from {link_data['url']}")
    driver = create_driver()
    if not driver: return None
    try:
        driver.get(link_data["url"])
        time.sleep(1)
        soup = BeautifulSoup(driver.page_source, "html.parser")
        og_img = soup.find("meta", property="og:image")
        image_url = og_img["content"].split("?")[0] if og_img else ""
        
        price = 99.00
        price_el = soup.select_one('[data-testid="price"]')
        if price_el:
            txt = price_el.get_text(strip=True).replace(",", "")
            nums = re.findall(r"[\d.]+", txt)
            if nums: price = float(nums[0])

        return {
            "name": link_data["title"], "image_url": image_url, "link": link_data["url"],
            "price": price, "width_cm": 80, "height_cm": 80, "depth_cm": 80 
        }
    finally:
        driver.quit()

# ==========================================
# 6. PIPELINE & USDZ EXPORT
# ==========================================

def export_usdz_manually(mesh, output_path):
    stage_path = output_path.replace(".usdz", ".usdc")
    stage = Usd.Stage.CreateNew(stage_path)
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)

    root = UsdGeom.Xform.Define(stage, '/Root')
    mesh_prim = UsdGeom.Mesh.Define(stage, '/Root/Model')

    points = mesh.vertices.tolist()
    face_vertex_counts = [len(f) for f in mesh.faces]
    face_vertex_indices = mesh.faces.flatten().tolist()

    mesh_prim.GetPointsAttr().Set(points)
    mesh_prim.GetFaceVertexCountsAttr().Set(face_vertex_counts)
    mesh_prim.GetFaceVertexIndicesAttr().Set(face_vertex_indices)

    if hasattr(mesh.visual, 'uv') and len(mesh.visual.uv) > 0:
        pv = UsdGeom.PrimvarsAPI(mesh_prim)
        uv_attr = pv.CreatePrimvar("st", Sdf.ValueTypeNames.TexCoord2fArray, UsdGeom.Tokens.faceVarying)
        uv_attr.Set(mesh.visual.uv.tolist())
        uv_attr.SetIndices(face_vertex_indices)

        material_path = '/Root/Material'
        material = UsdShade.Material.Define(stage, material_path)
        pbr_shader = UsdShade.Shader.Define(stage, material_path + '/PBRShader')
        pbr_shader.CreateIdAttr("UsdPreviewSurface")

        if hasattr(mesh.visual, 'material') and hasattr(mesh.visual.material, 'image'):
            tex_name = "texture.png"
            tex_full_path = os.path.join(os.path.dirname(stage_path), tex_name)
            mesh.visual.material.image.save(tex_full_path)

            t_shader = UsdShade.Shader.Define(stage, material_path + '/DiffuseTexture')
            t_shader.CreateIdAttr('UsdUVTexture')
            t_shader.CreateInput('file', Sdf.ValueTypeNames.Asset).Set(tex_name)
            t_shader.CreateInput("st", Sdf.ValueTypeNames.Float2).ConnectToSource(pbr_shader.ConnectableAPI(), "st")
            t_shader.CreateOutput('rgb', Sdf.ValueTypeNames.Float3)
            pbr_shader.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).ConnectToSource(t_shader.ConnectableAPI(), "rgb")
        
        UsdShade.MaterialBindingAPI(mesh_prim).Bind(material)

    stage.GetRootLayer().Save()
    UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(stage_path), output_path)
    return True

def run_pipeline_return_bytes(pil_img, output_format='usdz'):
    print(f"🎨 Stage 5: Starting TRELLIS Reconstruction (Output: {output_format.upper()})...")
    start_time = time.time()
    temp_dir = tempfile.mkdtemp()
    
    try:
        print("   🧹 Removing Background...")
        img = remove_background(pil_img.convert("RGBA"), rembg_session)
        img = resize_foreground(img, 0.85) 
        
        print("   🧠 Running TRELLIS Inference...")
        # Request both formats to satisfy to_glb requirements
        outputs = pipeline.run(
            img, 
            seed=1, 
            formats=["gaussian", "mesh"], 
            preprocess_image=False
        )
        
        # Extract results
        trellis_gaussian = outputs['gaussian'][0]
        trellis_mesh = outputs['mesh'][0]
        
        print("   🧱 Generating GLB from Gaussian + Mesh...")
        # Create GLB object using both inputs
        glb_object = postprocessing_utils.to_glb(
            trellis_gaussian, 
            trellis_mesh, 
            simplify=0.95, 
            texture_size=1024,
            verbose=False
        )
        
        # Save raw GLB (needed for both formats)
        raw_glb_path = os.path.join(temp_dir, "trellis_raw.glb")
        glb_object.export(raw_glb_path)

        # Load into Trimesh for post-processing
        tm = trimesh.load(raw_glb_path, file_type='glb', force='mesh')

        # --- Simple Post-Processing (No Auto-Leveling) ---
        # 1. Center on X/Z axis
        tm.apply_translation([-tm.centroid[0], 0, -tm.centroid[2]]) 
        # 2. Place on floor (Y=0)
        tm.apply_translation([0, -tm.bounds[0][1], 0])              

        # Calculate bounds for scaling logic later
        bmin, bmax = tm.bounds[0], tm.bounds[1]
        bounds_m = (max(bmax[0]-bmin[0], 0.01), max(bmax[1]-bmin[1], 0.01), max(bmax[2]-bmin[2], 0.01))

        if output_format == 'glb':
            print("   📦 Exporting GLB...")
            out_path = os.path.join(temp_dir, "output.glb")
            tm.export(out_path, file_type='glb')
            mimetype = "model/gltf-binary"
        else:
            print("   🔄 Converting to USDZ...")
            out_path = os.path.join(temp_dir, "output.usdz")
            export_usdz_manually(tm, out_path)
            mimetype = "model/vnd.usd+zip"

        with open(out_path, 'rb') as f:
            data = f.read()
            
        print(f"🎉 TRELLIS Pipeline Complete in {time.time() - start_time:.2f}s")
        return (data, mimetype, bounds_m)

    except Exception:
        print("❌ PIPELINE FATAL ERROR:")
        traceback.print_exc()
        raise
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

# ==========================================
# 7. ROUTES
# ==========================================

@app.route('/dream', methods=['POST'])
def dream():
    print("\n💤 DREAM REQUEST RECEIVED")
    query = request.form.get('query')
    if not query: return jsonify({"error": "No query provided"}), 400

    links = fetch_search_results(query, 1)
    if not links: return jsonify({"error": f"No results for {query}"}), 404
    
    product = fetch_product_details(links[0])
    if not product or not product.get('image_url'): return jsonify({"error": "Product found but no image"}), 500
    
    print(f"   📸 Found: {product['name']}")

    try:
        resp = requests.get(product['image_url'], timeout=10)
        img = Image.open(io.BytesIO(resp.content))
    except Exception as e: return jsonify({"error": f"Image download failed: {e}"}), 500

    try:
        glb_bytes, mimetype, _ = run_pipeline_return_bytes(img, output_format='glb')
        filename = f"{query.replace(' ', '_')}.glb"
        return Response(glb_bytes, mimetype=mimetype, headers={
            "Content-Disposition": f"attachment; filename={filename}"
        })
    except Exception as e:
        print(f"❌ Dream Pipeline Error: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/roomscan', methods=['POST'])
def roomscan_to_furniture():
    print("\n🚀 NEW ROOMSCAN REQUEST RECEIVED")
    if 'file' not in request.files: return jsonify({"error": "No file"}), 400
    room_type = request.form.get('room_type', 'living room')

    room_dims = get_room_dimensions_from_buffer(request.files['file'])
    if not room_dims: return jsonify({"error": "Invalid room scan file"}), 400

    suggestions = ask_gemini_for_furniture(room_dims, room_type, num_items=3)
    
    built = []
    for sugg in suggestions[:3]:
        query = sugg.get("furniture_query", "IKEA chair")
        links = fetch_search_results(query, 1)
        if not links: continue
        product = fetch_product_details(links[0])
        if not product or not product.get('image_url'): continue
        try:
            img_resp = requests.get(product['image_url'], timeout=10)
            img = Image.open(io.BytesIO(img_resp.content))
        except Exception: continue
        
        try:
            # Main app uses USDZ
            usdz_bytes, mimetype, bounds_m = run_pipeline_return_bytes(img, output_format='usdz')
            built.append((product, usdz_bytes, mimetype, bounds_m))
        except Exception as e:
            print(f"⚠️ Pipeline failed for {query}: {e}")
            continue

    if not built: return jsonify({"error": "Could not generate furniture"}), 500

    furniture_payloads = []
    for idx, (product, usdz_bytes, mimetype, bounds_m) in enumerate(built):
        model_id = str(uuid.uuid4())
        model_store[model_id] = (usdz_bytes, mimetype)
        
        # Simple floor layout logic
        rw, rd = room_dims["w"]/100.0, room_dims["d"]/100.0
        x_span, z_span = max(rw-0.8, 1.0), max(rd-0.8, 1.0)
        positions = [(0,0,0)]
        if len(built)==2: positions = [(-x_span/4,0,z_span/4), (x_span/4,0,z_span/4)]
        if len(built)==3: positions = [(0,0,z_span/4), (-x_span/3,0,-z_span/4), (x_span/3,0,-z_span/4)]
        
        px, py, pz = positions[idx] if idx < len(positions) else (0,0,0)
        bw, bh, bd = bounds_m
        sx = (product["width_cm"]/100.0)/bw if bw>0 else 1.0
        sy = (product["height_cm"]/100.0)/bh if bh>0 else 1.0
        sz = (product["depth_cm"]/100.0)/bd if bd>0 else 1.0

        furniture_payloads.append({
            "furniture_id": str(uuid.uuid4()),
            "usdz_url": f"/roomscan/model/{model_id}",
            "position": {"x": px, "y": py, "z": pz},
            "scale": {"x": sx, "y": sy, "z": sz},
            "page_link": product["link"],
            "price": str(int(product["price"])),
            "image_link": product["image_url"],
        })

    return jsonify({
        "scan_id": str(uuid.uuid4()),
        "plans": [{"plan_id": str(uuid.uuid4()), "furniture": furniture_payloads, "total_items": len(furniture_payloads)}],
        "total_plans": 1,
    })

@app.route('/roomscan/model/<model_id>', methods=['GET'])
def get_model(model_id):
    if model_id not in model_store: return jsonify({"error": "Model not found"}), 404
    data, mimetype = model_store.pop(model_id)
    return Response(data, mimetype=mimetype, headers={"Content-Disposition": f"attachment; filename=furniture.usdz"})

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "online", "gpu": torch.cuda.get_device_name(0), "model": "TRELLIS"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
