import DollyCore
import Foundation

/// The Record bar's state and the hotkey's meaning in each recording state (spec 4.1 and 3).
nonisolated public struct RecordBarModel: Sendable {
    public enum HotkeyCommand: Hashable, Sendable { case openBar, stop, cancelCountdown, ignore }

    public static let targets: [TargetKind] = [.window, .area, .display]
    public static let threadsWarning = "Longer than Threads allows"

    public var target: TargetKind = .window
    public var windowID: UInt32?

    public init() {}

    public var canRecord: Bool { target != .window || windowID != nil }

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
    public static let title = "Screen Recording"
    public static let message = "Dolly needs Screen Recording to record your screen. It never records until you press Record."
    public static let allow = "Allow Screen Recording"
    public static let openSettings = "Open System Settings"
    public static let deniedHint = "Screen Recording is still off. Turn on Dolly in System Settings, Privacy & Security, Screen & System Audio Recording."
}
