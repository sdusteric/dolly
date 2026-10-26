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
}
