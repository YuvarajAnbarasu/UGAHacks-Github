import SwiftUI
import RealityKit
import ARKit
import CryptoKit

// MARK: - Download and cache 3D models (USDZ or GLB)
extension ARViewContainer.Coordinator {
    private static func cacheKey(for url: URL) -> String {
        let input = Data(url.absoluteString.utf8)
        let hash = SHA256.hash(data: input)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

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
            throw NSError(domain: "ARViewContainer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Download failed or expired."])
        }
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        let isGLB = contentType.contains("gltf") || contentType.contains("glb")
        let ext = isGLB ? "glb" : "usdz"
        let fileURL = modelDir.appendingPathComponent(key).appendingPathExtension(ext)
        try data.write(to: fileURL)
        return fileURL
    }
}

/// Pending action from SwiftUI to coordinator (remove/cancel)
enum PendingARAction: Equatable {
    case none
    case removeSelected
    case cancelMove
}

/// Result of raycast for floor placement
enum RaycastPlacementResult {
    case valid(SIMD3<Float>)
    case outOfBounds  // Hit wall or invalid surface
}

struct ARViewContainer: UIViewRepresentable {
    let design: GeneratedDesign
    @Binding var selectedItemForPlacement: FurnitureItem?
    let isMoveMode: Bool
    @Binding var pendingAction: PendingARAction
    @Binding var placedItemIds: Set<UUID>
    @Binding var rotationGestureAngle: Angle
    var onPlaced: (() -> Void)?
    var onPlacedCountChanged: ((Int) -> Void)?
    var onOutOfBounds: (() -> Void)?

    func makeUIView(context: Context) -> UIView {
        guard RealityResourceManager.shared.requestSession(.arDesign) else {
            let arView = ARView(frame: .zero)
            context.coordinator.isBlocked = true
            context.coordinator.arView = arView
            return arView
        }

        let arView = ARView(frame: .zero)
        arView.translatesAutoresizingMaskIntoConstraints = false
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic

        let coord = context.coordinator
        coord.arView = arView
        coord.isBlocked = false
        coord.pendingConfig = config
        coord.pendingDesign = design
        coord.selectedItemForPlacement = selectedItemForPlacement
        coord.isMoveMode = isMoveMode
        coord.pendingAction = $pendingAction
        coord.placedItemIds = $placedItemIds
        coord.rotationGestureAngle = $rotationGestureAngle
        coord.onPlaced = onPlaced
        coord.onPlacedCountChanged = onPlacedCountChanged
        coord.onOutOfBounds = onOutOfBounds

        // Use a container view so our gestures capture touches before ARView's built-in pinch/zoom
        let container = UIView(frame: .zero)
        container.backgroundColor = .clear
        container.addSubview(arView)
        NSLayoutConstraint.activate([
            arView.topAnchor.constraint(equalTo: container.topAnchor),
            arView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            arView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            arView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        container.addGestureRecognizer(tapGesture)

        let rotationGesture = UIRotationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRotation(_:)))
        rotationGesture.delegate = coord
        rotationGesture.cancelsTouchesInView = false  // Allow tap to still work
        container.addGestureRecognizer(rotationGesture)

        NotificationCenter.default.addObserver(
            coord,
            selector: #selector(Coordinator.stopARSession),
            name: .stopAllARSessions,
            object: nil
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard !coord.isBlocked, !coord.hasRunSession else { return }
            guard let ar = coord.arView, let config = coord.pendingConfig else { return }
            coord.hasRunSession = true
            coord.pendingConfig = nil
            let design = coord.pendingDesign
            coord.pendingDesign = nil
            ar.session.run(config, options: .resetTracking)
            if let design = design {
                coord.setupPlacementMode(design: design)
            }
        }

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let arView = context.coordinator.arView else { return }
        if context.coordinator.isBlocked {
            arView.session.pause()
            return
        }
        context.coordinator.selectedItemForPlacement = selectedItemForPlacement
        context.coordinator.isMoveMode = isMoveMode
        context.coordinator.rotationGestureAngle = $rotationGestureAngle
        context.coordinator.onPlaced = onPlaced
        context.coordinator.onPlacedCountChanged = onPlacedCountChanged
        context.coordinator.onOutOfBounds = onOutOfBounds
        context.coordinator.handlePendingActionIfNeeded()
        context.coordinator.applyRotationFromSwiftUI()
        // Disable ARView's pinch so our rotation gesture can recognize
        disablePinchRecursively(in: arView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func disablePinchRecursively(in view: UIView) {
        view.gestureRecognizers?.forEach { if $0 is UIPinchGestureRecognizer { $0.isEnabled = false } }
        view.subviews.forEach { disablePinchRecursively(in: $0) }
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var arView: ARView?
        var isBlocked = false
        var hasRunSession = false
        var pendingConfig: ARWorldTrackingConfiguration?
        var pendingDesign: GeneratedDesign?
        var selectedItemForPlacement: FurnitureItem?
        var isMoveMode: Bool = false
        var onPlaced: (() -> Void)?
        var onPlacedCountChanged: ((Int) -> Void)?
        var onOutOfBounds: (() -> Void)?

        var placedEntities: [(entity: Entity, item: FurnitureItem)] = []

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true  // Allow pinch-rotate and tap to work together
        }
        var selectedEntityForMove: Entity?
        var furnitureCache: [UUID: Entity] = [:]
        var rotationStartAngle: Float = 0
        var pendingAction: Binding<PendingARAction>?
        var placedItemIds: Binding<Set<UUID>>?
        var rotationGestureAngle: Binding<Angle>?
        var rotationBaseOrientation: simd_quatf?

        // Ghost preview for move mode
        var ghostEntity: Entity?
        var ghostAnchor: AnchorEntity?
        var trackedRaycast: ARTrackedRaycast?
        var lastGhostPosition: SIMD3<Float>?
        var ghostIsValid = false

        @objc func stopARSession() {
            stopGhostPreview()
            arView?.session.pause()
            Task { @MainActor in
                RealityResourceManager.shared.releaseSession(.arDesign)
            }
        }

        deinit {
            stopGhostPreview()
            Task { @MainActor in
                RealityResourceManager.shared.releaseSession(.arDesign)
            }
        }

        func setupPlacementMode(design: GeneratedDesign) {
            Task { @MainActor in
                await preloadFurnitureModels(design.furniture)
                onPlacedCountChanged?(0)
            }
        }

        @MainActor
        private func preloadFurnitureModels(_ furniture: [FurnitureItem]) async {
            for item in furniture {
                guard let urlString = item.modelUrlUsdz, let modelURL = URL(string: urlString) else { continue }
                do {
                    let localURL = try await Self.localModelURL(from: modelURL)
                    let entity = try await Entity.load(contentsOf: localURL)
                    entity.name = item.id.uuidString
                    furnitureCache[item.id] = entity
                } catch {
                    print("❌ Failed to preload \(item.name): \(error)")
                }
            }
        }

        @objc func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            guard isMoveMode, ghostEntity != nil || selectedEntityForMove != nil else { return }
            switch gesture.state {
            case .began:
                if let entity = selectedEntityForMove {
                    let q = entity.orientation
                    rotationStartAngle = 2 * atan2(q.vector.y, q.vector.w)
                } else if let ghost = ghostEntity {
                    let q = ghost.orientation
                    rotationStartAngle = 2 * atan2(q.vector.y, q.vector.w)
                }
            case .changed:
                let angle = rotationStartAngle + Float(gesture.rotation)
                let rot = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
                selectedEntityForMove?.orientation = rot
                ghostEntity?.orientation = rot
            default:
                break
            }
        }

        @MainActor
        func applyRotationFromSwiftUI() {
            guard let binding = rotationGestureAngle else { return }
            let angle = binding.wrappedValue
            guard angle.radians != 0 else {
                rotationBaseOrientation = nil
                return
            }
            let target = ghostEntity ?? selectedEntityForMove
            guard target != nil else { return }
            if rotationBaseOrientation == nil {
                rotationBaseOrientation = target!.orientation
            }
            guard let base = rotationBaseOrientation else { return }
            let rot = simd_quatf(angle: Float(angle.radians), axis: SIMD3<Float>(0, 1, 0))
            let newOrientation = base * rot
            selectedEntityForMove?.orientation = newOrientation
            ghostEntity?.orientation = newOrientation
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = arView, gesture.state == .ended else { return }
            let sourceView = gesture.view ?? arView
            let location = gesture.location(in: sourceView)
            let locationInARView = arView.convert(location, from: sourceView)

            Task { @MainActor in
                let tapPoint = locationInARView
                // 1. In move mode with ghost: tap ghost = cancel. Tap elsewhere = raycast from tap and place there
                if isMoveMode, ghostEntity != nil, let entity = selectedEntityForMove {
                    // Tap on ghost = cancel move (tap same item again)
                    if tapHitsGhost(tapPoint, in: arView) {
                        stopGhostPreview()
                        selectedEntityForMove = nil
                        return
                    }
                    // Tap on ground: raycast from tap location, place at that point
                    switch raycastFloorHit(from: tapPoint, in: arView) {
                    case .valid(let hitPosition):
                        if placedEntities.contains(where: { $0.entity === entity }) {
                            let bounds = entity.visualBounds(relativeTo: entity)
                            let bottomOffset = -bounds.min.y
                            entity.position = SIMD3<Float>(hitPosition.x, hitPosition.y + bottomOffset, hitPosition.z)
                            entity.orientation = ghostEntity?.orientation ?? entity.orientation
                            entity.isEnabled = true
                            stopGhostPreview()
                            selectedEntityForMove = nil
                        }
                    case .outOfBounds:
                        onOutOfBounds?()
                    case nil:
                        break
                    }
                    return
                }

                // 2. In move mode: tap entity to select for move (or tap same item again = cancel, handled above)
                if isMoveMode, let hitEntity = entityAt(point: tapPoint, in: arView),
                   let idx = placedEntities.firstIndex(where: { $0.entity === hitEntity }) {
                    startGhostPreview(entity: placedEntities[idx].entity, item: placedEntities[idx].item)
                    selectedEntityForMove = hitEntity
                    hitEntity.isEnabled = false
                    return
                }

                // 3. Raycast for placement – use view coordinates for tap accuracy
                let rayResult = raycastFloorHit(from: tapPoint, in: arView)
                guard case .valid(let hitPosition) = rayResult else {
                    if case .outOfBounds = rayResult { onOutOfBounds?() }
                    return
                }

                // 4. Place new furniture if we have a selected item
                guard let item = selectedItemForPlacement, let templateEntity = furnitureCache[item.id] else {
                    return
                }

                // One item per type: don't place duplicates
                guard !placedEntities.contains(where: { $0.item.id == item.id }) else { return }

                let cloneEntity = templateEntity.clone(recursive: true)
                cloneEntity.name = item.id.uuidString
                addCollisionToEntity(cloneEntity)

                let scaleX = Float(item.placement?.scale.x ?? 1.0)
                let scaleY = Float(item.placement?.scale.y ?? 1.0)
                let scaleZ = Float(item.placement?.scale.z ?? 1.0)
                cloneEntity.scale = SIMD3<Float>(x: scaleX, y: scaleY, z: scaleZ)

                let localBounds = cloneEntity.visualBounds(relativeTo: cloneEntity)
                let bottomOffset = -localBounds.min.y
                let floorY = hitPosition.y + bottomOffset

                let anchor = AnchorEntity(world: .zero)
                cloneEntity.position = SIMD3<Float>(hitPosition.x, floorY, hitPosition.z)
                anchor.addChild(cloneEntity)
                arView.scene.addAnchor(anchor)

                placedEntities.append((entity: cloneEntity, item: item))
                syncPlacedItemIds()
                onPlaced?()
                onPlacedCountChanged?(placedEntities.count)
            }
        }

        /// Raycast from view point; returns .valid(hit) for floor, .outOfBounds if first hit is wall. Prevents placement through walls.
        private func raycastFloorHit(from viewPoint: CGPoint, in arView: ARView) -> RaycastPlacementResult? {
            // Ensure point is within view bounds (required for makeRaycastQuery)
            let bounds = arView.bounds
            let clampedPoint = CGPoint(
                x: min(max(viewPoint.x, 0), bounds.width - 1),
                y: min(max(viewPoint.y, 0), bounds.height - 1)
            )
            var results: [ARRaycastResult] = []
            var query: ARRaycastQuery?
            // Use .any FIRST to get closest hit (wall or floor) – required for out-of-bounds detection
            let targets: [(ARRaycastQuery.Target, ARRaycastQuery.TargetAlignment)] = [
                (.existingPlaneGeometry, .any),
                (.existingPlaneInfinite, .any),
                (.existingPlaneGeometry, .horizontal),
                (.existingPlaneInfinite, .horizontal),
                (.estimatedPlane, .any),
                (.estimatedPlane, .horizontal)
            ]
            for (target, alignment) in targets {
                query = arView.makeRaycastQuery(from: clampedPoint, allowing: target, alignment: alignment)
                if let q = query {
                    results = arView.session.raycast(q)
                    if !results.isEmpty { break }
                }
            }
            guard let first = results.first else { return nil }
            let normal = SIMD3<Float>(
                first.worldTransform.columns.1.x,
                first.worldTransform.columns.1.y,
                first.worldTransform.columns.1.z
            )
            let dotUp = simd_dot(normal, SIMD3<Float>(0, 1, 0))
            // First hit is wall (vertical) = out of bounds; don't place through walls
            if dotUp < 0.7 {
                return .outOfBounds
            }
            let hitPos = SIMD3<Float>(
                first.worldTransform.columns.3.x,
                first.worldTransform.columns.3.y,
                first.worldTransform.columns.3.z
            )
            return .valid(hitPos)
        }

        private func syncPlacedItemIds() {
            placedItemIds?.wrappedValue = Set(placedEntities.map { $0.item.id })
        }

        @MainActor
        func handlePendingActionIfNeeded() {
            guard let action = pendingAction?.wrappedValue, action != .none else { return }
            switch action {
                case .removeSelected:
                    if let entity = selectedEntityForMove,
                       let idx = placedEntities.firstIndex(where: { $0.entity === entity }) {
                        let (e, _) = placedEntities.remove(at: idx)
                        if let anchor = e.parent as? AnchorEntity {
                            anchor.removeFromParent()
                        } else {
                            e.parent?.removeChild(e)
                        }
                        syncPlacedItemIds()
                        onPlacedCountChanged?(placedEntities.count)
                    }
                    stopGhostPreview()
                    selectedEntityForMove = nil
                case .cancelMove:
                    stopGhostPreview()
                    selectedEntityForMove = nil
                case .none:
                    break
            }
            pendingAction?.wrappedValue = .none
        }

        // MARK: - Ghost Preview (Move Mode)

        private func startGhostPreview(entity: Entity, item: FurnitureItem) {
            stopGhostPreview()

            let ghost = entity.clone(recursive: true)
            ghost.name = "ghost_\(entity.name)"

            let scaleX = Float(item.placement?.scale.x ?? 1.0)
            let scaleY = Float(item.placement?.scale.y ?? 1.0)
            let scaleZ = Float(item.placement?.scale.z ?? 1.0)
            ghost.scale = SIMD3<Float>(x: scaleX, y: scaleY, z: scaleZ)
            ghost.orientation = entity.orientation
            addCollisionToEntity(ghost)

            applyGhostMaterial(to: ghost, isValid: false)

            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(ghost)
            arView?.scene.addAnchor(anchor)

            ghostEntity = ghost
            ghostAnchor = anchor
            lastGhostPosition = nil
            ghostIsValid = false

            startTrackedRaycast(for: ghost, item: item)
        }

        private func startTrackedRaycast(for ghost: Entity, item: FurnitureItem) {
            guard let arView = arView, let frame = arView.session.currentFrame else { return }

            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            let rayPoint = viewPointToImagePoint(center, viewBounds: arView.bounds, imageResolution: frame.camera.imageResolution)
            var query = frame.raycastQuery(from: rayPoint, allowing: .existingPlaneGeometry, alignment: .horizontal)
            if arView.session.raycast(query).isEmpty {
                query = frame.raycastQuery(from: rayPoint, allowing: .estimatedPlane, alignment: .horizontal)
            }

            trackedRaycast = arView.session.trackedRaycast(query) { [weak self] results in
                guard let self = self, let first = results.first else {
                    DispatchQueue.main.async {
                        self?.updateGhostPosition(nil, isValid: false, ghost: ghost, item: item)
                    }
                    return
                }

                let normal = SIMD3<Float>(
                    first.worldTransform.columns.1.x,
                    first.worldTransform.columns.1.y,
                    first.worldTransform.columns.1.z
                )
                let isValid = simd_dot(normal, SIMD3<Float>(0, 1, 0)) > 0.7

                let hitPosition = SIMD3<Float>(
                    first.worldTransform.columns.3.x,
                    first.worldTransform.columns.3.y,
                    first.worldTransform.columns.3.z
                )

                let localBounds = ghost.visualBounds(relativeTo: ghost)
                let bottomOffset = -localBounds.min.y
                let placementPos = SIMD3<Float>(hitPosition.x, hitPosition.y + bottomOffset, hitPosition.z)

                DispatchQueue.main.async {
                    self.updateGhostPosition(placementPos, isValid: isValid, ghost: ghost, item: item)
                }
            }
        }

        @MainActor
        private func updateGhostPosition(_ position: SIMD3<Float>?, isValid: Bool, ghost: Entity, item: FurnitureItem) {
            guard ghostEntity === ghost else { return }

            if let pos = position {
                ghost.position = pos
                lastGhostPosition = pos
            }
            ghostIsValid = isValid
            applyGhostMaterial(to: ghost, isValid: isValid)
        }

        private func applyGhostMaterial(to entity: Entity, isValid: Bool) {
            let color: UIColor = isValid
                ? UIColor(white: 1, alpha: 0.4)
                : UIColor(red: 1, green: 0.25, blue: 0.25, alpha: 0.55)
            let mat = SimpleMaterial(color: color, isMetallic: false)

            if let model = entity as? ModelEntity {
                model.model?.materials = [mat]
            }
            entity.children.forEach { applyGhostMaterial(to: $0, isValid: isValid) }
        }

        private func stopGhostPreview() {
            trackedRaycast?.stopTracking()
            trackedRaycast = nil
            ghostAnchor?.removeFromParent()
            ghostAnchor = nil
            ghostEntity = nil
            lastGhostPosition = nil
            ghostIsValid = false
            rotationBaseOrientation = nil
            rotationGestureAngle?.wrappedValue = .zero
            if let entity = selectedEntityForMove {
                entity.isEnabled = true
            }
        }

        private func addCollisionToEntity(_ entity: Entity) {
            if let modelEntity = entity as? ModelEntity {
                modelEntity.generateCollisionShapes(recursive: true)
            }
            entity.children.forEach { addCollisionToEntity($0) }
        }

        private func viewPointToImagePoint(_ viewPoint: CGPoint, viewBounds: CGRect, imageResolution: CGSize) -> CGPoint {
            let viewSize = viewBounds.size
            let scaleW = imageResolution.width / viewSize.width
            let scaleH = imageResolution.height / viewSize.height
            let scale = min(scaleW, scaleH)
            let offsetX = (imageResolution.width - viewSize.width * scale) / 2
            let offsetY = (imageResolution.height - viewSize.height * scale) / 2
            return CGPoint(x: viewPoint.x * scale + offsetX, y: viewPoint.y * scale + offsetY)
        }

        private func tapHitsGhost(_ point: CGPoint, in arView: ARView) -> Bool {
            guard let ghost = ghostEntity else { return false }
            let results = arView.hitTest(point, query: .nearest)
            return results.contains { result in
                var current: Entity? = result.entity
                while let e = current {
                    if e === ghost { return true }
                    current = e.parent
                }
                return false
            }
        }

        private func entityAt(point: CGPoint, in arView: ARView) -> Entity? {
            let results = arView.hitTest(point, query: .nearest)
            return results.compactMap { result -> Entity? in
                var current: Entity? = result.entity
                while let e = current {
                    if placedEntities.contains(where: { $0.entity === e }) {
                        return e
                    }
                    current = e.parent
                }
                return nil
            }.first
        }
    }
}

