import DollyCore
import Foundation

/// The Record bar's state and the hotkey's meaning in each recording state (spec 4.1 and 3).
nonisolated public struct RecordBarModel: Sendable {
    public enum HotkeyCommand: Hashable, Sendable { case openBar, stop, cancelCountdown, ignore }
    /// What turning on a switch needs first (Snap's first-run pattern: why, one button, then a hint).
    public enum PermissionStep: Hashable, Sendable { case askCamera, askMicrophone, cameraDenied, microphoneDenied }

    public static let targets: [TargetKind] = [.window, .area, .display]
    public static let threadsWarning = "Longer than Threads allows"

    public var target: TargetKind = .window
    public var windowID: UInt32?
    /// Record the camera and microphone beside the screen; both off until the owner turns them on.
    public var camera = false
    public var microphone = false
    /// nil is the system's default device.
    public var cameraID: String?
    public var microphoneID: String?

    public init() {}

    public var canRecord: Bool { target != .window || windowID != nil }

    /// The first thing a switch that is on still needs from macOS, camera first.
    public func permissionStep(camera cameraAccess: DevicePermission, microphone micAccess: DevicePermission) -> PermissionStep? {
        if camera, cameraAccess != .allowed { return cameraAccess == .notAsked ? .askCamera : .cameraDenied }
        if microphone, micAccess != .allowed { return micAccess == .notAsked ? .askMicrophone : .microphoneDenied }
        return nil
    }

    /// The devices to record, or nil where the switch is off. An empty ID means the default device.
    public func apply(to plan: inout RecordingPlan) {
        plan.cameraID = camera ? (cameraID ?? "") : nil
        plan.microphoneID = microphone ? (microphoneID ?? "") : nil
    }

    public mutating func load(from settings: Settings) {
        camera = settings.recordCamera
        microphone = settings.recordMicrophone
        cameraID = settings.cameraID
        microphoneID = settings.microphoneID
    }

    public func store(in settings: inout Settings) {
        settings.recordCamera = camera
        settings.recordMicrophone = microphone
        settings.cameraID = cameraID
        settings.microphoneID = microphoneID
    }

    /// Each time the bar opens it picks the window the owner was looking at: the frontmost app's top
    /// window, or the top window when Dolly itself is in front. `windows` is ordered front to back.
    public mutating func prepare(windows: [PickableWindow], frontmostPID: Int32?) {
        windowID = (windows.first { $0.pid == frontmostPID } ?? windows.first)?.id
    }

    /// The owner brought another window to the front while the bar is open: pick it, as long as the
    /// bar offers it. Returns whether the pick changed.
    public mutating func follow(frontWindow id: UInt32, in windows: [PickableWindow]) -> Bool {
        guard id != windowID, windows.contains(where: { $0.id == id }) else { return false }
        windowID = id
        return true
    }

    public static func label(_ target: TargetKind) -> String {
        switch target {
        case .window: "Window"
        case .area: "Area"
        case .display: "Display"
        }
    }

    public static func hotkey(in state: RecordingController.State) -> HotkeyCommand {
        switch state {
        case .idle, .failed: .openBar
        case .recording: .stop
        case .countdown: .cancelCountdown
        case .finishing: .ignore
        }
    }

    public static func timerText(elapsed: Double) -> String { TimeText.short(elapsed) }

    /// Over five minutes the tooltip warns that Threads will refuse the clip (spec 4.2).
    public static func tooltip(elapsed: Double, shortcut: String) -> String {
        let stop = "Stop recording (\(shortcut))"
        return elapsed > RecordingPlan.warnSeconds ? stop + ". " + threadsWarning : stop
    }
}

nonisolated public enum PermissionWindowModel {
    public struct Copy: Sendable, Hashable {
        public let title: String
        public let message: String
        public let allow: String
        public let deniedHint: String
    }

    public static let screen = Copy(title: title, message: message, allow: allow, deniedHint: deniedHint)
    public static let camera = Copy(
        title: "Camera",
        message: "Dolly needs Camera to record your camera. It never opens the camera unless the Camera switch is on.",
        allow: "Allow Camera",
        deniedHint: "Camera is still off. Turn on Dolly in System Settings, Privacy & Security, Camera."
    )
    public static let microphone = Copy(
        title: "Microphone",
        message: "Dolly needs Microphone to record your voice. It never opens the microphone unless the Microphone switch is on.",
        allow: "Allow Microphone",
        deniedHint: "Microphone is still off. Turn on Dolly in System Settings, Privacy & Security, Microphone."
    )

    public static let title = "Screen Recording"
    public static let message = "Dolly needs Screen Recording to record your screen. It never records until you press Record."
    public static let allow = "Allow Screen Recording"
    public static let openSettings = "Open System Settings"
    public static let deniedHint = "Screen Recording is still off. Turn on Dolly in System Settings, Privacy & Security, Screen & System Audio Recording."
}
