import SwiftUI
import RoomPlan
import Combine
import AVFoundation
import Foundation
import SceneKit
import ModelIO
import SceneKit.ModelIO

// MARK: - Ensure unique naming to avoid conflicts

// MARK: - Coordinator (TOP-LEVEL, stable name + NSCoding)

@available(iOS 16.0, *)
@objc(RoomPlanCaptureCoordinator)
final class RoomPlanCaptureCoordinator: NSObject, NSCoding, RoomCaptureSessionDelegate, RoomCaptureViewDelegate {
    private var capturedRoomURLBinding: Binding<URL?>
    let captureController: RoomPlanCaptureController
    weak var captureView: RoomPlan.RoomCaptureView?
    private var latestRoom: CapturedRoom?
    
    // Progress tracking for "stuck" detection
    private var lastProgressTime = Date()
    private var lastWallCount = 0
    private var lastObjectCount = 0

    init(capturedRoomURL: Binding<URL?>, captureController: RoomPlanCaptureController) {
        self.capturedRoomURLBinding = capturedRoomURL
        self.captureController = captureController
        super.init()
    }
    
    private var capturedRoomURL: URL? {
        get { capturedRoomURLBinding.wrappedValue }
        set { capturedRoomURLBinding.wrappedValue = newValue }
    }

    // NSCoding requirements (RoomCaptureViewDelegate inherits NSCoding)
    required init?(coder: NSCoder) { 
        // This shouldn't be called in normal usage, but we need to satisfy the protocol
        fatalError("init(coder:) not supported") 
    }
    func encode(with coder: NSCoder) { /* no-op */ }

    func stopSession() {
        print("🛑 stopSession called from coordinator")
        guard let session = captureView?.captureSession else {
            print("⚠️ No capture session to stop")
            return
        }
        // RoomPlan requires stop() on main thread
        Task { @MainActor in
            session.stop()
            self.captureView = nil
        }
    }

    // MARK: - RoomCaptureSessionDelegate

    /// Auto-complete when room looks done: 4+ walls and no new geometry for 12s
    private let autoCompleteWallsThreshold = 4
    private let autoCompleteStallSeconds: TimeInterval = 12
    private var didTriggerAutoComplete = false

    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        let walls = room.walls.count
        let objects = room.objects.count
        print("🔄 Session didUpdate room: \(walls) walls, \(objects) objects")
        
        Task { @MainActor in
            captureController.updateRoomWallCount(walls)
        }
        // Track geometry progress for "stuck" detection
        if walls != lastWallCount || objects != lastObjectCount {
            lastWallCount = walls
            lastObjectCount = objects
            lastProgressTime = Date()
            print("📈 Geometry progress detected - walls: \(lastWallCount) -> \(walls), objects: \(lastObjectCount) -> \(objects)")
            
            DispatchQueue.main.async { [weak captureController] in
                captureController?.markGeometryProgress()
            }
        } else {
            let stalledFor = Date().timeIntervalSince(lastProgressTime)
            if stalledFor > 5 { // Log every 5s when no progress
                print("⏱️ No geometry progress for \(String(format: "%.1f", stalledFor))s")
            }
            // Auto-complete when room has enough walls and scanning has stalled
            if !didTriggerAutoComplete, walls >= autoCompleteWallsThreshold, stalledFor >= autoCompleteStallSeconds {
                didTriggerAutoComplete = true
                print("✅ Auto-completing: room has \(walls) walls and no progress for \(Int(stalledFor))s")
                stopSession()
            }
        }
        
        DispatchQueue.main.async { [weak captureController] in
            captureController?.didReceiveUpdate()
        }
    }

    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        print("🏁 Session didEndWith - Error: \(error?.localizedDescription ?? "None")")
        if let error = error {
            print("❌ Capture ended with error: \(error)")
            return
        }

        guard let room = latestRoom else {
            print("❌ No captured room available for export")
            DispatchQueue.main.async { [weak captureController] in
                captureController?.isExporting = false
            }
            return
        }

        DispatchQueue.main.async { [weak captureController] in
            captureController?.isExporting = true
        }
        Task.detached { [weak self] in
            do {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let url = docs.appendingPathComponent("CapturedRoom_\(UUID().uuidString).usdz")
                try room.export(to: url)
                print("✅ Room exported to: \(url)")

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.captureController.isExporting = false
                    self.captureController.exportCompleteFileName = url.lastPathComponent
                    // Brief "Room saved" then go straight to "Room Scanned Successfully!" (skip Explore screen)
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2s
                        guard let self else { return }
                        self.captureController.exportCompleteFileName = nil
                        self.capturedRoomURLBinding.wrappedValue = url
                        self.captureController.dismissAfterExport = true
                    }
                }
            } catch {
                print("❌ Export failed: \(error)")
                await MainActor.run {
                    self?.captureController.isExporting = false
                    self?.captureController.exportCompleteFileName = nil
                }
            }
        }
    }

    func captureSession(_ session: RoomCaptureSession, didAdd room: CapturedRoom) {
        print("➕ Session didAdd room")
        latestRoom = room
    }
    
    func captureSession(_ session: RoomCaptureSession, didChange room: CapturedRoom) {
        print("📝 Session didChange room")
        latestRoom = room
    }
    
    func captureSession(_ session: RoomCaptureSession, didRemove room: CapturedRoom) {
        print("➖ Session didRemove room")
    }

    func captureSession(_ session: RoomCaptureSession, didStartWith configuration: RoomCaptureSession.Configuration) {
        print("🚀 Session didStartWith configuration")
        DispatchQueue.main.async { [weak captureController] in
            captureController?.sessionDidStart()
        }
    }

    func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {
        let text: String
        switch instruction {
        case .moveCloseToWall: text = "Move closer to the wall"
        case .moveAwayFromWall: text = "Move away from the wall"
        case .slowDown: text = "Slow down"
        case .turnOnLight: text = "Turn on more lights"
        case .normal: text = "Keep scanning"
        case .lowTexture: text = "More texture needed"
        @unknown default: text = "Continue scanning"
        }
        print("📋 Session didProvide instruction: \(text)")
        DispatchQueue.main.async { [weak captureController] in
            captureController?.updateInstruction(text)
        }
    }

    // MARK: - RoomCaptureViewDelegate

    func captureView(_ roomCaptureView: RoomPlan.RoomCaptureView, didPresent processedResult: CapturedRoom, error: Error?) {
        print("🎯 captureView didPresent processedResult")
        if let error = error {
            print("❌ RoomCaptureView error: \(error)")
            return
        }
        print("✅ Captured room with \(processedResult.walls.count) walls, \(processedResult.objects.count) objects")
        latestRoom = processedResult
    }
}

// MARK: - SwiftUI View

// MARK: - Interactive USDZ room view (drag to rotate, pinch to zoom – full exploration)
@available(iOS 16.0, *)
struct RoomModelPreviewView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView(frame: .zero)
        sceneView.backgroundColor = UIColor(white: 0.08, alpha: 1)
        sceneView.autoenablesDefaultLighting = true
        sceneView.allowsCameraControl = true
        sceneView.antialiasingMode = .multisampling4X
        
        // Load full USDZ as a scene so RoomPlan's full hierarchy (walls, floor, ceiling) is preserved
        let container: SCNNode
        let scene = SCNScene()
        if let loadedScene = try? SCNScene(url: url, options: nil) {
            container = SCNNode()
            for child in loadedScene.rootNode.childNodes {
                container.addChildNode(child)
            }
            scene.rootNode.addChildNode(container)
        } else {
            container = SCNNode()
            scene.rootNode.addChildNode(container)
            let mdlAsset = MDLAsset(url: url)
            for i in 0..<mdlAsset.count {
                let obj = mdlAsset.object(at: i)
                container.addChildNode(SCNNode(mdlObject: obj))
            }
        }
        
        // Bounding box of full room: merge all nodes in hierarchy
        var minP = SCNVector3(Float.greatestFiniteMagnitude, .greatestFiniteMagnitude, .greatestFiniteMagnitude)
        var maxP = SCNVector3(-Float.greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
        func mergeBox(of node: SCNNode) {
            let (mn, mx) = node.boundingBox
            for (sx, sy, sz) in [(1, 1, 1), (1, 1, -1), (1, -1, 1), (1, -1, -1), (-1, 1, 1), (-1, 1, -1), (-1, -1, 1), (-1, -1, -1)] {
                let x = sx == 1 ? mx.x : mn.x
                let y = sy == 1 ? mx.y : mn.y
                let z = sz == 1 ? mx.z : mn.z
                let world = node.convertPosition(SCNVector3(x, y, z), to: container)
                minP.x = min(minP.x, world.x)
                minP.y = min(minP.y, world.y)
                minP.z = min(minP.z, world.z)
                maxP.x = max(maxP.x, world.x)
                maxP.y = max(maxP.y, world.y)
                maxP.z = max(maxP.z, world.z)
            }
            for child in node.childNodes { mergeBox(of: child) }
        }
        for child in container.childNodes { mergeBox(of: child) }
        if minP.x == Float.greatestFiniteMagnitude { minP = SCNVector3(0, 0, 0); maxP = SCNVector3(1, 1, 1) }
        
        let cx = (minP.x + maxP.x) * 0.5
        let cy = (minP.y + maxP.y) * 0.5
        let cz = (minP.z + maxP.z) * 0.5
        let dx = maxP.x - minP.x
        let dy = maxP.y - minP.y
        let dz = maxP.z - minP.z
        let extent = max(dx, dy, dz, 1.0)
        let distance = extent * 1.6
        
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 55
        cam.position = SCNVector3(cx + distance * 0.5, cy + distance * 0.5, cz + distance * 0.5)
        let lookAt = SCNLookAtConstraint(target: container)
        lookAt.isGimbalLockEnabled = true
        cam.constraints = [lookAt]
        scene.rootNode.addChildNode(cam)
        sceneView.pointOfView = cam
        sceneView.scene = scene
        
        return sceneView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {}
}

// MARK: - Full-screen room review: move room to explore entire USDZ, then Confirm / Rescan
@available(iOS 16.0, *)
struct RoomCapturePreviewScreen: View {
    let roomFileURL: URL
    let onConfirm: () -> Void
    let onRescan: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Explore your room")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.top, 20)
            
            Text("Drag to rotate · Pinch to zoom")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 4)
            
            RoomModelPreviewView(url: roomFileURL)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            HStack(spacing: 16) {
                Button(action: onRescan) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Rescan")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundColor(Theme.Colors.darkBrown)
                    .background(Color.white)
                    .cornerRadius(14)
                }
                
                Button(action: onConfirm) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Use this room")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundColor(.white)
                    .background(
                        LinearGradient(
                            colors: [Theme.Colors.mediumBrown, Theme.Colors.darkBrown],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

@available(iOS 16.0, *)
struct RoomPlanCaptureViewFixed: View {
    @Environment(\.dismiss) var dismiss
    @Binding var capturedRoomURL: URL?
    @StateObject private var captureController = RoomPlanCaptureController()
    @State private var coordinator: RoomPlanCaptureCoordinator?
    /// Delay creating RoomPlan view to avoid Metal/RealityKit conflict (tonemap LUT crash)
    @State private var scannerReady = false

    var body: some View {
        ZStack {
            if scannerReady {
                RoomPlanCaptureViewRepresentable(
                    capturedRoomURL: $capturedRoomURL,
                    captureController: captureController,
                    onCoordinatorCreated: { coord in
                        coordinator = coord
                    }
                )
                .edgesIgnoringSafeArea(.all)
            } else {
                Color.black
                    .ignoresSafeArea()
                VStack(spacing: Theme.Spacing.md) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Preparing scanner...")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    Text("Releasing camera for room scan")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
            }

            if !captureController.showPreview {
            VStack(alignment: .leading, spacing: 0) {
                // Top row: close button top-left, instruction card top-right (so 3D preview stays visible at bottom)
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    Button {
                        coordinator?.stopSession()
                        captureController.stopSession()
                        dismiss()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 44, height: 44)
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 4)
                    }

                    Spacer(minLength: 0)

                    // Instruction card in top-right so room preview is visible below
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: captureController.scanningState.iconName)
                            .font(.system(size: captureController.scanningState == .scanning ? 28 : 22, weight: .semibold))
                            .foregroundColor(captureController.scanningState.iconColor)

                        Text(captureController.scanningState.displayTitle)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)

                        Text(captureController.scanningState.displaySubtitle)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                        
                        if let instruction = captureController.currentInstruction, 
                           !instruction.contains("Session may be stuck") {
                            Text("RoomPlan: \(instruction)")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.top, 2)
                        }
                        
                        if captureController.scanningState == .lowQuality || captureController.scanningState == .stuck {
                            HStack(spacing: Theme.Spacing.sm) {
                                Button("Try Again") {
                                    captureController.markGeometryProgress()
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Theme.Colors.mediumBrown)
                                .cornerRadius(12)
                                
                                Button("Complete Anyway") {
                                    coordinator?.stopSession()
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(12)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: 260)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.xl)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.xl)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                captureController.scanningState.iconColor.opacity(0.3),
                                                captureController.scanningState.iconColor.opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                    )
                    .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 8)
                }
                .padding(Theme.Spacing.lg)

                Spacer(minLength: 0)
            }
        }
        }
        .animation(.easeInOut(duration: 0.45), value: captureController.showPreview)
        .overlay {
            if captureController.isExporting {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                VStack(spacing: Theme.Spacing.md) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Saving room file...")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Creating USDZ")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(Theme.Spacing.xl)
            }
            if let name = captureController.exportCompleteFileName {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.green)
                    Text("Room saved")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    Text(name)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .onAppear {
            // CRITICAL: Avoid Metal/RealityKit crash (tonemap LUT / shader library conflict).
            // Stop any AR session and wait for Metal to fully tear down before creating RoomPlan.
            RealityResourceManager.shared.forceStopAllSessions()
            
            guard RealityResourceManager.shared.requestSession(.roomPlan) else {
                print("❌ RoomPlan blocked - could not get exclusive access")
                dismiss()
                return
            }
            
            // Delay before creating RoomPlan view and starting session so Metal/RealityKit
            // from any previous AR view is fully released (prevents fsSurfaceShadow texture crash).
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                scannerReady = true
                captureController.startSession()
            }
        }
        .onDisappear {
            // Ensure proper cleanup order
            coordinator?.stopSession()
            captureController.stopSession()
            RealityResourceManager.shared.releaseSession(.roomPlan)
            coordinator = nil
        }
        .onChange(of: captureController.capturedURL) { _, newValue in
            if let url = newValue {
                capturedRoomURL = url
                dismiss()
            }
        }
        .onChange(of: captureController.dismissAfterExport) { _, shouldDismiss in
            if shouldDismiss {
                captureController.dismissAfterExport = false
                dismiss()
            }
        }
        .alert("Unsupported Device", isPresented: $captureController.showUnsupportedDeviceAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your device does not support RoomPlan. Please use a device with LiDAR capabilities.")
        }
        .alert("Camera Access Required", isPresented: $captureController.cameraPermissionDenied) {
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel") { dismiss() }
        } message: {
            Text("Camera access is required for room scanning. Please enable camera access in Settings.")
        }
        .alert("Scanning Tips", isPresented: $captureController.isStuck) {
            Button("Continue Scanning") { captureController.isStuck = false }
            Button("Complete Scan") {
                coordinator?.stopSession()
            }
        } message: {
            Text("For large rooms, try:\n• Move slowly and steadily\n• Ensure good lighting\n• Point camera at wall-floor edges\n• Get close to walls when instructed\n• Complete scan if you've covered the main areas")
        }
    }
}

// MARK: - Scanning States
enum RoomPlanScanningState: Equatable {
    case scanning
    case lowQuality
    case stuck
    
    var displayTitle: String {
        switch self {
        case .scanning: return "Scanning Your Room"
        case .lowQuality: return "Can't Analyze Surface Yet"
        case .stuck: return "Room Analysis Stuck"
        }
    }
    
    var displaySubtitle: String {
        switch self {
        case .scanning: return "Move slowly around the room to capture all walls and objects"
        case .lowQuality: return "Try moving to a corner with better lighting or more texture"
        case .stuck: return "Move to a different area or complete the current scan"
        }
    }
    
    var iconName: String {
        switch self {
        case .scanning: return "viewfinder.circle.fill"
        case .lowQuality: return "exclamationmark.triangle.fill"
        case .stuck: return "xmark.circle.fill"
        }
    }
    
    var iconColor: Color {
        switch self {
        case .scanning: return .white
        case .lowQuality: return .orange
        case .stuck: return .red
        }
    }
}

// MARK: - Controller

@available(iOS 16.0, *)
@MainActor
final class RoomPlanCaptureController: ObservableObject {
    @Published var currentInstruction: String?
    @Published var capturedURL: URL?
    @Published var isRoomPlanSupported: Bool = true
    @Published var showUnsupportedDeviceAlert: Bool = false
    @Published var cameraPermissionDenied: Bool = false
    @Published var canStartSession: Bool = false
    @Published var didStart: Bool = false
    @Published var isStuck: Bool = false
    @Published var sessionProgress: String = "Initializing..."
    @Published var scanningState: RoomPlanScanningState = .scanning
    @Published var isExporting: Bool = false
    @Published var exportCompleteFileName: String?
    @Published var showPreview: Bool = false
    @Published var pendingPreviewURL: URL?
    /// When true, room capture view should dismiss (skip "Explore your room" and go to Room Scanned Successfully!)
    @Published var dismissAfterExport: Bool = false
    
    // Track session state for debugging
    @Published var hasReceivedInstructions = false
    @Published var hasReceivedUpdates = false
    @Published var sessionStartTime: Date?
    @Published var isStartingSession = false

    private var instructionTimer: Timer?
    private var progressWatchdog: Timer?
    private let stuckTimeoutInterval: TimeInterval = 45.0
    
    // Progress tracking for geometry-based stuck detection
    private var lastProgressTime = Date()
    private var lastInstruction: String?
    private var lastInstructionChange = Date()
    /// When 4+ walls, don't show "Try Again / Complete Anyway" (auto-complete will run)
    private var roomWallCount: Int = 0
    
    // Thresholds for quality detection
    private let lowQualityThreshold: TimeInterval = 10  // Same instruction for 10s
    private let stuckGeometryThreshold: TimeInterval = 25  // No geometry for 25s

    init() { 
        isRoomPlanSupported = RoomCaptureSession.isSupported
        print("📱 Device Info:")
        print("   - RoomPlan supported: \(isRoomPlanSupported)")
        print("   - Device: \(UIDevice.current.model)")
        print("   - System: \(UIDevice.current.systemVersion)")
    }

    func startSession() {
        // Prevent multiple concurrent session starts
        guard !isStartingSession else { 
            print("⚠️ Session start already in progress")
            return 
        }
        
        // Verify we have exclusive RealityKit access
        guard RealityResourceManager.shared.canStartSession(.roomPlan) else {
            print("❌ Cannot start RoomPlan - RealityKit resources unavailable")
            sessionProgress = "Resource conflict detected"
            showUnsupportedDeviceAlert = true
            return
        }
        
        print("🎯 startSession called")
        isStartingSession = true
        sessionStartTime = Date()
        sessionProgress = "Checking device support..."
        
        // Check RoomPlan support (LiDAR requirement)
        guard isRoomPlanSupported else {
            print("❌ RoomPlan not supported on this device")
            sessionProgress = "Device not supported"
            showUnsupportedDeviceAlert = true
            isStartingSession = false
            return
        }
        
        print("✅ RoomPlan is supported")
        sessionProgress = "Checking permissions..."
        
        // Reset session state
        sessionDidStartCalled = false
        hasReceivedInstructions = false
        hasReceivedUpdates = false
        isStuck = false
        scanningState = .scanning
        lastProgressTime = Date()
        lastInstructionChange = Date()
        roomWallCount = 0
        
        checkCameraPermissions { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                self.isStartingSession = false
                if granted {
                    print("✅ Camera permission granted")
                    self.sessionProgress = "Ready to scan"
                    self.canStartSession = true
                } else {
                    print("❌ Camera permission denied")
                    self.sessionProgress = "Camera permission denied"
                    self.cameraPermissionDenied = true
                }
            }
        }
    }

    func stopSession() {
        print("🛑 stopSession called from controller")
        canStartSession = false
        didStart = false
        isStartingSession = false
        sessionDidStartCalled = false
        isStuck = false
        scanningState = .scanning
        roomWallCount = 0
        dismissAfterExport = false
        instructionTimer?.invalidate()
        instructionTimer = nil
        progressWatchdog?.invalidate()
        progressWatchdog = nil
    }

    func updateInstruction(_ instruction: String?) {
        print("📋 updateInstruction called: \(instruction ?? "nil")")
        currentInstruction = instruction
        hasReceivedInstructions = true
        
        if let startTime = sessionStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            print("⏱️ Instruction received after \(String(format: "%.1f", elapsed))s")
        }
        
        // Check for repeated instruction (low quality detection)
        let newInstruction = instruction ?? ""
        if newInstruction != lastInstruction {
            lastInstruction = newInstruction
            lastInstructionChange = Date()
            if scanningState == .lowQuality {
                scanningState = .scanning
            }
        } else {
            let instructionStalledFor = Date().timeIntervalSince(lastInstructionChange)
            if instructionStalledFor > lowQualityThreshold {
                print("⚠️ Same instruction for \(String(format: "%.1f", instructionStalledFor))s")
                scanningState = .lowQuality
            }
        }
        
        restartInstructionTimer()
    }

    private var sessionDidStartCalled = false
    
    func sessionDidStart() {
        guard !sessionDidStartCalled else { return }
        sessionDidStartCalled = true
        print("✅ sessionDidStart called")
        if let startTime = sessionStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            print("⏱️ Session started after \(String(format: "%.1f", elapsed))s")
        }
        sessionProgress = "Session active"
        startProgressWatchdog()
        restartInstructionTimer()
    }
    
    func didReceiveUpdate() {
        if !hasReceivedUpdates {
            hasReceivedUpdates = true
            if let startTime = sessionStartTime {
                let elapsed = Date().timeIntervalSince(startTime)
                print("⏱️ First room update after \(String(format: "%.1f", elapsed))s")
            }
        }
    }
    
    func markGeometryProgress() {
        print("✅ markGeometryProgress called")
        lastProgressTime = Date()
        if scanningState != .scanning {
            scanningState = .scanning
        }
    }
    
    func updateRoomWallCount(_ count: Int) {
        roomWallCount = count
    }
    
    private func startProgressWatchdog() {
        print("🐕 Starting progress watchdog")
        progressWatchdog?.invalidate()
        lastProgressTime = Date()
        
        progressWatchdog = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let geometryStalledFor = Date().timeIntervalSince(self.lastProgressTime)
            let wallCount = self.roomWallCount
            
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // Don't show warning when room has 4+ walls — auto-complete will run; showing "Try Again" is confusing
                if wallCount >= 4 { return }
                if geometryStalledFor > self.stuckGeometryThreshold {
                    print("❌ No geometry progress for \(String(format: "%.1f", geometryStalledFor))s - marking as STUCK")
                    self.scanningState = .stuck
                } else if geometryStalledFor > self.lowQualityThreshold && self.scanningState == .scanning {
                    print("⚠️ No geometry progress for \(String(format: "%.1f", geometryStalledFor))s - marking as LOW QUALITY")
                    self.scanningState = .lowQuality
                }
            }
        }
    }

    private func restartInstructionTimer() {
        instructionTimer?.invalidate()
        instructionTimer = Timer.scheduledTimer(withTimeInterval: stuckTimeoutInterval, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.isStuck = true
                self?.currentInstruction = "Session may be stuck - try moving around or tap Complete to finish"
            }
        }
    }

    private func checkCameraPermissions(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { completion($0) }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
}

// MARK: - UIViewRepresentable

@available(iOS 16.0, *)
struct RoomPlanCaptureViewRepresentable: UIViewRepresentable {
    @Binding var capturedRoomURL: URL?
    @ObservedObject var captureController: RoomPlanCaptureController
    
    // Use a callback instead of binding for the coordinator
    let onCoordinatorCreated: (RoomPlanCaptureCoordinator) -> Void

    func makeUIView(context: Context) -> RoomPlan.RoomCaptureView {
        let view = RoomPlan.RoomCaptureView(frame: .zero)
        view.delegate = context.coordinator

        if let session = view.captureSession {
            session.delegate = context.coordinator
        }

        context.coordinator.captureView = view
        return view
    }

    func updateUIView(_ uiView: RoomPlan.RoomCaptureView, context: Context) {
        guard Thread.isMainThread else { return }
        guard captureController.canStartSession,
              !captureController.didStart,
              !captureController.isStartingSession,
              let session = uiView.captureSession
        else { return }

        // Defer session start to next run loop to avoid "Modifying state during view update"
        captureController.didStart = true
        DispatchQueue.main.async {
            print("🔍 Starting RoomPlan session on main thread")
            let config = RoomCaptureSession.Configuration()
            session.run(configuration: config)
        }
    }

    func makeCoordinator() -> RoomPlanCaptureCoordinator {
        let coord = RoomPlanCaptureCoordinator(capturedRoomURL: $capturedRoomURL, captureController: captureController)
        onCoordinatorCreated(coord)
        return coord
    }
}
