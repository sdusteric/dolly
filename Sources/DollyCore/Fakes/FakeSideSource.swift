import Foundation
import Synchronization

/// A camera or microphone that writes a few placeholder bytes and reports a chosen first sample time,
/// optionally failing to start or giving out mid-take.
public final class FakeSideSource: SideSource {
    public let firstHost: Double
    public let failsToStart: Bool
    public let failsAtHost: Double?
    private let state = Mutex((deviceID: String?.none, started: false, stopped: false))

    public init(firstHost: Double, failsToStart: Bool = false, failsAtHost: Double? = nil) {
        self.firstHost = firstHost
        self.failsToStart = failsToStart
        self.failsAtHost = failsAtHost
    }

    public var deviceID: String? { state.withLock { $0.deviceID } }
    public var started: Bool { state.withLock { $0.started } }
    public var stopped: Bool { state.withLock { $0.stopped } }

    public func start(deviceID: String, url: URL, failed: @escaping @Sendable (SideSourceFailure) -> Void) async throws -> Double {
        state.withLock {
            $0.deviceID = deviceID
            $0.started = true
        }
        if failsToStart { throw RecordingSourceError.couldNotStart("fake device") }
        try Data([0, 0, 0, 8]).write(to: url)
        if let failsAtHost { failed(SideSourceFailure(hostTime: failsAtHost, reason: "unplugged")) }
        return firstHost
    }

    public func stop() async throws {
        state.withLock { $0.stopped = true }
    }
}
