import SwiftUI
import Combine

/// Coordinates exclusive use of camera/Metal between AR design view and RoomPlan.
/// Does NOT import RealityKit/ARKit so that during room scan our app doesn't load
/// RealityKit—only RoomPlan does—avoiding the tonemapLUT Metal crash (fsSurfaceShadow).
@MainActor
class RealityResourceManager: ObservableObject {
    static let shared = RealityResourceManager()
    
    @Published private var activeSession: SessionType?
    
    enum SessionType {
        case arDesign
        case roomPlan
    }
    
    private init() {}
    
    /// Request exclusive access to RealityKit resources
    func requestSession(_ type: SessionType) -> Bool {
        if let active = activeSession, active != type {
            print("🚫 RealityKit session denied - \(active) is active")
            return false
        }
        
        activeSession = type
        print("✅ RealityKit session granted for \(type)")
        return true
    }
    
    /// Release RealityKit resources
    func releaseSession(_ type: SessionType) {
        guard activeSession == type else { return }
        activeSession = nil
        print("🔓 RealityKit session released for \(type)")
    }
    
    /// Force stop all AR/RealityKit sessions
    func forceStopAllSessions() {
        activeSession = nil
        NotificationCenter.default.post(name: .stopAllARSessions, object: nil)
        print("🛑 Force stopped all RealityKit sessions")
    }
    
    /// Check if a specific session type can be started
    func canStartSession(_ type: SessionType) -> Bool {
        return activeSession == nil || activeSession == type
    }
}

extension Notification.Name {
    static let stopAllARSessions = Notification.Name("StopAllARSessions")
}
