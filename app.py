import torch
import os
import io
import time
import rembg
import trimesh
import numpy as np
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


def rotation_matrix_from_vectors(vec1, vec2):
    """ Find the rotation matrix that aligns vec1 to vec2 """
    a, b = (vec1 / np.linalg.norm(vec1)), (vec2 / np.linalg.norm(vec2))
    v = np.cross(a, b)
    c = np.dot(a, b)
    s = np.linalg.norm(v)
    
    # If vectors are parallel, return identity
    if s == 0:
        return np.eye(4)
        
    kmat = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    rotation_matrix = np.eye(3) + kmat + kmat.dot(kmat) * ((1 - c) / (s ** 2))
    
    # Create 4x4 matrix
    M = np.eye(4)
    M[:3, :3] = rotation_matrix
    return M

def geometry_auto_level(mesh):
    """
    Aligns the object by finding the average plane of the bottom 10% of points.
    """
    try:
        vertices = mesh.vertices
        
        # 1. Find the "Feet" (Bottom 10% of vertices)
        min_y = np.min(vertices[:, 1])
        max_y = np.max(vertices[:, 1])
        height_threshold = min_y + (max_y - min_y) * 0.1
        
        # Get all points that are part of the base
        feet_points = vertices[vertices[:, 1] < height_threshold]
        
        if len(feet_points) < 10:
            return mesh

        # 2. Fit a plane to these points (PCA / SVD)
        centroid = np.mean(feet_points, axis=0)
        centered = feet_points - centroid
        u, s, vh = np.linalg.svd(centered.T)
        normal = u[:, -1] 
        
        # Ensure normal points UP (positive Y)
        if normal[1] < 0:
            normal = -normal
            
        # 3. Calculate the tilt angle
        up_vector = np.array([0, 1, 0])
        dot = np.dot(normal, up_vector)
        dot = max(min(dot, 1.0), -1.0) 
        angle_deg = np.degrees(np.arccos(dot))
        
        print(f"   📐 Detected Tilt: {angle_deg:.2f}°")
        
        # 4. SAFETY CHECK: Only correct small/medium tilts (< 20 degrees)
        if angle_deg > 0.5 and angle_deg < 20.0:
            # Calculate rotation needed to make the normal point straight UP
            R = rotation_matrix_from_vectors(normal, up_vector)
            mesh.apply_transform(R)
            print("   ✅ Mesh leveled.")
        else:
            print(f"   ⚠️ Tilt {angle_deg:.2f}° outside safe range (0.5-20°). Skipping.")
            
    except Exception as e:
        print(f"   ⚠️ Leveling failed: {e}")
    
    return mesh


@app.route('/generate', methods=['POST'])
def generate():
    if 'image' not in request.files:
        return jsonify({"error": "No image file provided"}), 400
    
    start_time = time.time()
    
    try:
        # A. Load & Process
        file = request.files['image']
        img = Image.open(file.stream).convert("RGBA")
        img = remove_background(img, rembg_session)
        img = resize_foreground(img, 0.85)
        
        # B. Inference
        with torch.no_grad():
            with torch.autocast(device_type=device, dtype=torch.bfloat16) if "cuda" in device else nullcontext():
                result = model.run_image([img], bake_resolution=1024, remesh="none", vertex_count=-1)
                mesh_sf3d = result[0] if isinstance(result, (list, tuple)) else result
            
        # C. Export to Trimesh
        temp_buffer = io.BytesIO()
        mesh_sf3d.export(temp_buffer, file_type='glb')
        temp_buffer.seek(0)
        tm = trimesh.load(temp_buffer, file_type='glb', force='mesh')
        
        # --- D. APPLY GEOMETRY FIX (Bottom 10%) ---
        tm = geometry_auto_level(tm)
        # ------------------------------------------

        # E. Final Export
        output_buffer = io.BytesIO()
        tm.export(output_buffer, file_type='glb')
        output_buffer.seek(0)
        
        duration = time.time() - start_time
        print(f"🎉 Generated in {duration:.2f}s")
        
        return send_file(output_buffer, mimetype='model/gltf-binary', as_attachment=True, download_name='model.glb')
        
    except Exception as e:
        print(f"❌ ERROR: {e}")
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
