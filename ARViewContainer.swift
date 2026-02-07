import SwiftUI
import RealityKit
import ARKit
import CryptoKit

// MARK: - Download and cache 3D models (USDZ or GLB); stable cache so reopening View in AR reuses files
extension ARViewContainer.Coordinator {
    /// Stable cache key for a remote URL so we reuse the same file when reopening View in AR (server URLs are one-time).
    private static func cacheKey(for url: URL) -> String {
        let input = Data(url.absoluteString.utf8)
        let hash = SHA256.hash(data: input)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Resolves a URL to a local file: use existing cache if present, else download and save with correct extension (USDZ or GLB).
    @MainActor
    static func localModelURL(from url: URL) async throws -> URL {
        if url.isFileURL { return url }
        let fm = FileManager.default
        let cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let modelDir = cacheDir.appendingPathComponent("FurnisherUSDZ", isDirectory: true)
        if !fm.fileExists(atPath: modelDir.path) {
            try fm.createDirectory(at: modelDir, withIntermediateDirectories: true)
        }
        let key = cacheKey(for: url)
        let usdzPath = modelDir.appendingPathComponent(key).appendingPathExtension("usdz")
        let glbPath = modelDir.appendingPathComponent(key).appendingPathExtension("glb")
        if fm.fileExists(atPath: usdzPath.path) { return usdzPath }
        if fm.fileExists(atPath: glbPath.path) { return glbPath }

        var request = URLRequest(url: url)
        request.setValue("1", forHTTPHeaderField: "ngrok-skip-browser-warning")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "ARViewContainer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Download failed or expired (one-time URL). Re-open the design from the result screen once."])
        }
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        let isGLB = contentType.contains("gltf") || contentType.contains("glb")
        let ext = isGLB ? "glb" : "usdz"
        let fileURL = modelDir.appendingPathComponent(key).appendingPathExtension(ext)
        try data.write(to: fileURL)
        return fileURL
    }
}

struct ARViewContainer: UIViewRepresentable {
    let design: GeneratedDesign
    
    func makeUIView(context: Context) -> ARView {
        // CRITICAL: Request exclusive access to RealityKit resources
        guard RealityResourceManager.shared.requestSession(.arDesign) else {
            print("❌ ARView blocked - RoomPlan session active")
            // Return empty view that won't initialize RealityKit
            let arView = ARView(frame: .zero)
            context.coordinator.isBlocked = true
            return arView
        }
        
        let arView = ARView(frame: .zero)
        
        // ARKit Configuration
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        
        let coord = context.coordinator
        coord.arView = arView
        coord.isBlocked = false
        coord.pendingConfig = config
        coord.pendingDesign = design
        
        NotificationCenter.default.addObserver(
            coord,
            selector: #selector(Coordinator.stopARSession),
            name: .stopAllARSessions,
            object: nil
        )
        
        // Delay session run so Metal/camera from RoomPlan (or previous AR) can fully tear down.
        // Prevents [CAMetalLayer nextDrawable] nil and FigCaptureSourceRemote conflicts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard !coord.isBlocked, !coord.hasRunSession else { return }
            guard let ar = coord.arView, let config = coord.pendingConfig else { return }
            coord.hasRunSession = true
            coord.pendingConfig = nil
            let design = coord.pendingDesign
            coord.pendingDesign = nil
            ar.session.run(config, options: .resetTracking)
            if let design = design {
                coord.loadScene(into: ar, design: design)
            }
        }
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Handle session blocking
        if context.coordinator.isBlocked {
            // Stop any running session
            uiView.session.pause()
            return
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        weak var arView: ARView?
        var isBlocked = false
        var hasRunSession = false
        var pendingConfig: ARWorldTrackingConfiguration?
        var pendingDesign: GeneratedDesign?
        
        @objc func stopARSession() {
            print("🛑 Stopping AR session for RoomPlan compatibility")
            arView?.session.pause()
            // Release RealityKit resources
            Task { @MainActor in
                RealityResourceManager.shared.releaseSession(.arDesign)
            }
        }
        
        deinit {
            // Ensure resources are released when coordinator is deallocated
            Task { @MainActor in
                RealityResourceManager.shared.releaseSession(.arDesign)
            }
        }
        
        func loadScene(into arView: ARView, design: GeneratedDesign) {
            // Don't load if blocked
            guard !isBlocked else { return }
            
            Task { @MainActor in
                // Step 1: Load room model if available
                if let roomModel = design.roomModel {
                    await loadRoomModel(roomModel, into: arView)
                }
                
                // Step 2: Load furniture
                await loadFurnitureModels(design.furniture, into: arView)
            }
        }
        
        // MARK: - Load Room Model (USDZ → RealityKit: local file or download then load)
        @MainActor
        private func loadRoomModel(_ roomModel: RoomModel, into arView: ARView) async {
            guard let urlString = roomModel.roomModelUrlUsdz,
                  let modelURL = URL(string: urlString) else {
                print("❌ Invalid room model URL")
                return
            }

            do {
                let isFileURL = modelURL.isFileURL
                print("📦 Room: \(isFileURL ? "local file" : "download/cache…")")
                let localURL = try await Self.localModelURL(from: modelURL)
                let roomEntity: Entity
                do {
                    roomEntity = try await Entity.load(contentsOf: localURL)
                } catch {
                    if !isFileURL { try? FileManager.default.removeItem(at: localURL) }
                    throw error
                }
                roomEntity.position = SIMD3<Float>(x: 0, y: 0, z: 0)
                if isFileURL {
                    let displayScale: Float = 0.5
                    roomEntity.scale = SIMD3<Float>(repeating: displayScale)
                } else if let dimensions = roomModel.dimensions {
                    let scale = Float(min(dimensions.width, dimensions.depth) / 3.0)
                    roomEntity.scale = SIMD3<Float>(repeating: scale)
                }
                let anchor = AnchorEntity(world: .zero)
                anchor.addChild(roomEntity)
                arView.scene.addAnchor(anchor)
                print("✅ Room loaded in RealityKit")
            } catch {
                print("❌ Failed to load room model: \(error)")
            }
        }
        
        // MARK: - Load Furniture Models (USDZ → RealityKit: download to temp file then load)
        @MainActor
        private func loadFurnitureModels(_ furniture: [FurnitureItem], into arView: ARView) async {
            for item in furniture {
                guard let urlString = item.modelUrlUsdz,
                      let modelURL = URL(string: urlString) else {
                    print("❌ Invalid furniture URL for \(item.name)")
                    continue
                }

                do {
                    print("🪑 Furniture: \(item.name) (\(modelURL.isFileURL ? "local" : "download/cache…"))")
                    let localURL = try await Self.localModelURL(from: modelURL)
                    let furnitureEntity: Entity
                    do {
                        furnitureEntity = try await Entity.load(contentsOf: localURL)
                    } catch {
                        try? FileManager.default.removeItem(at: localURL)
                        throw error
                    }

                    if let placement = item.placement {
                        furnitureEntity.position = SIMD3<Float>(
                            x: Float(placement.position.x),
                            y: Float(placement.position.y),
                            z: Float(placement.position.z)
                        )
                        furnitureEntity.orientation = simd_quatf(
                            angle: Float(placement.rotation.y),
                            axis: SIMD3<Float>(0, 1, 0)
                        )
                        furnitureEntity.scale = SIMD3<Float>(
                            x: Float(placement.scale.x),
                            y: Float(placement.scale.y),
                            z: Float(placement.scale.z)
                        )
                    }

                    let anchor = AnchorEntity(world: .zero)
                    anchor.addChild(furnitureEntity)
                    arView.scene.addAnchor(anchor)
                    print("✅ \(item.name) loaded in RealityKit")
                } catch {
                    print("❌ Failed to load \(item.name): \(error)")
                }
            }
        }
    }
}
