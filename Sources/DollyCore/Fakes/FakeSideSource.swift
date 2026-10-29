import Foundation
import Synchronization

/// A camera or microphone that writes a few placeholder bytes and reports a chosen first sample time,
/// optionally failing to start or giving out mid-take.
public final class FakeSideSource: SideSource {
    public let firstHost: Double
    public let failsToStart: Bool
    public let failsAtHost: Double?
    /// Waits up to a second for this source to start too, the way two real devices warm up together.
    public let peer: FakeSideSource?
    /// Read when `start` is called, to see the recorder's state at that moment.
    public nonisolated(unsafe) var report: @MainActor () -> String = { "" }
    private let state = Mutex((deviceID: String?.none, started: false, stopped: false, sawPeer: false, stateAtStart: ""))

    public init(firstHost: Double, failsToStart: Bool = false, failsAtHost: Double? = nil, waitsFor peer: FakeSideSource? = nil) {
        self.firstHost = firstHost
        self.failsToStart = failsToStart
        self.failsAtHost = failsAtHost
        self.peer = peer
    }

    public var sawPeerStart: Bool { state.withLock { $0.sawPeer } }
    public var stateAtStart: String { state.withLock { $0.stateAtStart } }

    public var deviceID: String? { state.withLock { $0.deviceID } }
    public var started: Bool { state.withLock { $0.started } }
    public var stopped: Bool { state.withLock { $0.stopped } }

    public func start(deviceID: String, url: URL, failed: @escaping @Sendable (SideSourceFailure) -> Void) async throws -> Double {
        let now = await report()
        state.withLock {
            $0.deviceID = deviceID
            $0.started = true
            $0.stateAtStart = now
        }
        if let peer {
            for _ in 0..<100 where !peer.started { try await Task.sleep(for: .milliseconds(10)) }
            let saw = peer.started
            state.withLock { $0.sawPeer = saw }
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
