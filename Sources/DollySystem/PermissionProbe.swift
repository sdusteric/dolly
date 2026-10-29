import AVFoundation
import CoreGraphics
import Foundation

/// Screen Recording permission (Snap's design section 13). `preflight()` never prompts.
/// `requestOnce()` shows the system dialog and is called only from the first-run window's button.
public enum PermissionProbe {
    public static let screenRecordingSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )

    public static func preflight() -> Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    public static func requestOnce() -> Bool { CGRequestScreenCaptureAccess() }

    public enum Status: Sendable, Hashable { case allowed, denied, notAsked }

    public static let cameraSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
    public static let microphoneSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")

    /// Camera and microphone access without prompting.
    public static func camera() -> Status { status(.video) }
    public static func microphone() -> Status { status(.audio) }

    /// Shows the system prompt; called only when the owner turns the switch on.
    public static func requestCamera() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }
    public static func requestMicrophone() async -> Bool { await AVCaptureDevice.requestAccess(for: .audio) }

    static func status(_ type: AVMediaType) -> Status {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: .allowed
        case .notDetermined: .notAsked
        default: .denied
        }
    }
}
