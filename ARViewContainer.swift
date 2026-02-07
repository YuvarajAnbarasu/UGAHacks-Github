import SwiftUI
import RealityKit
import ARKit

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
        
        // Store reference for cleanup
        context.coordinator.arView = arView
        context.coordinator.isBlocked = false
        
        // Listen for stop notifications
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(context.coordinator.stopARSession),
            name: .stopAllARSessions,
            object: nil
        )
        
        arView.session.run(config)
        
        // Load models asynchronously
        context.coordinator.loadScene(into: arView, design: design)
        
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
        
        // MARK: - Load Room Model
        @MainActor
        private func loadRoomModel(_ roomModel: RoomModel, into arView: ARView) async {
            guard let urlString = roomModel.roomModelUrlUsdz,
                  let modelURL = URL(string: urlString) else {
                print("❌ Invalid room model URL")
                return
            }

            do {
                print("📦 Loading room model from: \(modelURL)")

                // Load entity using Entity.load (compatible with iOS 15+)
                let roomEntity = try await Entity.load(contentsOf: modelURL)

                // Position at origin
                roomEntity.position = SIMD3<Float>(x: 0, y: 0, z: 0)

                // Optional: Scale based on dimensions
                if let dimensions = roomModel.dimensions {
                    let scale = Float(min(dimensions.width, dimensions.depth) / 3.0)
                    roomEntity.scale = SIMD3<Float>(repeating: scale)
                }

                // Add to AR scene
                let anchor = AnchorEntity(world: .zero)
                anchor.addChild(roomEntity)
                arView.scene.addAnchor(anchor)

                print("✅ Room model loaded")

            } catch {
                print("❌ Failed to load room model: \(error)")
            }
        }
        
        // MARK: - Load Furniture Models
        @MainActor
        private func loadFurnitureModels(_ furniture: [FurnitureItem], into arView: ARView) async {
            for item in furniture {
                guard let modelURL = URL(string: item.modelUrlUsdz ?? "") else {
                    print("❌ Invalid furniture URL for \(item.name)")
                    continue
                }
                
                do {
                    print("🪑 Loading: \(item.name)")

                    // Load entity using Entity.load (compatible with iOS 15+)
                    let furnitureEntity = try await Entity.load(contentsOf: modelURL)

                    // Apply placement
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

                    // Add to scene
                    let anchor = AnchorEntity(world: .zero)
                    anchor.addChild(furnitureEntity)
                    arView.scene.addAnchor(anchor)

                    print("✅ \(item.name) loaded")

                } catch {
                    print("❌ Failed to load \(item.name): \(error)")
                }
            }
        }
    }
}
