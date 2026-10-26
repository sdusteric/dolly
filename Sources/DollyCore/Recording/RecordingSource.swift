import Foundation

/// Why a recording stopped (Snap's design 20.6, with Dolly's names).
public enum RecordingStopReason: String, Sendable, Hashable, Codable {
    case user, hotkey, windowClosed, displayDisconnected, streamFailed, diskFull, maxLength, quit, sleep

    /// The note a take keeps, nil when the owner or Dolly stopped on purpose.
    public var note: String? {
        switch self {
        case .user, .hotkey, .quit, .sleep: nil
        case .windowClosed: "Stopped: the window closed"
        case .displayDisconnected: "Stopped: the display was disconnected"
        case .streamFailed: "Stopped: the recording failed"
        case .diskFull: "Stopped: disk almost full"
        case .maxLength: "Stopped: 30 minutes is the longest take"
        }
    }
}

public enum RecordingEvent: Sendable, Hashable {
    case started(hostTime: Double)
    case stalled
    case stopped(RecordingStopReason)
}

public struct RecordingResult: Sendable, Hashable {
    public var duration: Double
    public var startHost: Double
    public init(duration: Double, startHost: Double) {
        self.duration = duration
        self.startHost = startHost
    }
}

public enum RecordingSourceError: Error, Sendable, Hashable { case couldNotStart(String), notRecording }

/// The screen recorder. `LiveRecordingSource` (DollySystem) uses ScreenCaptureKit;
/// `FakeRecordingSource` writes synthetic frames through the same `MasterWriter`.
public protocol RecordingSource: AnyObject, Sendable {
    func start(plan: RecordingPlan, movieURL: URL, events: @escaping @Sendable (RecordingEvent) -> Void) async throws
    func stop() async throws -> RecordingResult
}

/// Samples the pointer and the recorded window's frame while recording (spec 4.3 and 4.4).
public protocol PointerSampling: AnyObject {
    func start(pointerURL: URL, windowLogURL: URL?, windowID: UInt32?) throws
    func stop() throws
}

/// Host clock seconds and waiting, so the countdown runs instantly in tests.
public protocol DollyClock: AnyObject, Sendable {
    func now() -> Double
    func sleep(seconds: Double) async
}

public protocol DiskSpaceProbing: AnyObject, Sendable {
    func freeBytes(at url: URL) -> Int64?
}

/// Names a zoom from the frame at its click (spec 4.6). The fallback is the click's time.
public protocol ZoomNaming: Sendable {
    func name(for click: Click, movie: URL, take: Take) async -> String
}

public struct FallbackZoomNamer: ZoomNaming {
    public init() {}
    public func name(for click: Click, movie: URL, take: Take) async -> String { "Click at \(TimeText.clock(click.t))" }
}
