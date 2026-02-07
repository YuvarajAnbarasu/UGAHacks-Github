import torch
import os
import io
import time
import rembg
from flask import Flask, request, send_file, jsonify
from flask_cors import CORS
from sf3d.system import SF3D
from sf3d.utils import remove_background, resize_foreground
from PIL import Image
from contextlib import nullcontext

app = Flask(__name__)
CORS(app)

# --- 1. GLOBAL INIT ---
print("⏳ INITIALIZING: Loading SF3D Model...")
device = "cuda" if torch.cuda.is_available() else "cpu"

try:
    # Load Model (Matches run.py exactly)
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

# Pre-load background remover
print("⏳ INITIALIZING: Loading Background Remover...")
rembg_session = rembg.new_session()

print("✅ SERVER READY! Waiting for requests...")


@app.route('/health', methods=['GET'])
def health():
    return jsonify({
        "status": "online", 
        "gpu": torch.cuda.get_device_name(0)
    })

@app.route('/generate', methods=['POST'])
def generate():
    if 'image' not in request.files:
        return jsonify({"error": "No image file provided"}), 400
    
    start_time = time.time()
    
    try:
        # A. Load Image
        file = request.files['image']
        img = Image.open(file.stream).convert("RGBA")
        
        # B. Pre-process (Remove Background)
        img = remove_background(img, rembg_session)
        img = resize_foreground(img, 0.85)
        
        # C. Inference
        with torch.no_grad():
            with torch.autocast(device_type=device, dtype=torch.bfloat16) if "cuda" in device else nullcontext():
                # run_image returns either a single mesh OR a list of meshes
                result = model.run_image(
                    [img], 
                    bake_resolution=1024, 
                    remesh="none", 
                    vertex_count=-1
                )
                
                # SAFETY FIX: Handle both list and single object return types
                if isinstance(result, (list, tuple)):
                    mesh = result[0]
                else:
                    mesh = result
            
        # D. Export (Raw, no fancy physics)
        output_buffer = io.BytesIO()
        mesh.export(output_buffer, file_type='glb', include_normals=True)
        output_buffer.seek(0)
        
        duration = time.time() - start_time
        print(f"🎉 Generated in {duration:.2f}s")
        
        return send_file(
            output_buffer, 
            mimetype='model/gltf-binary',
            as_attachment=True, 
            download_name='model.glb'
        )
        
    except Exception as e:
        print(f"❌ ERROR: {e}")
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
