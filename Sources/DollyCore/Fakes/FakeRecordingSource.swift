import AVFoundation
import Foundation
import Synchronization

/// Writes a real `take.mov` of plain frames through `MasterWriter`, as fast as it can, so the
/// controller and the writer are tested without a screen.
public final class FakeRecordingSource: RecordingSource {
    public struct Options: Sendable, Hashable {
        public var seconds: Double
        public var failOnStart: Bool
        public var startHost: Double
        /// Sent after the last frame, as ScreenCaptureKit does when the window closes.
        public var stopEvent: RecordingStopReason?
        public init(seconds: Double, failOnStart: Bool = false, startHost: Double = 0, stopEvent: RecordingStopReason? = nil) {
            self.seconds = seconds
            self.failOnStart = failOnStart
            self.startHost = startHost
            self.stopEvent = stopEvent
        }
    }

    public let options: Options
    private let task = Mutex<Task<Void, any Error>?>(nil)
    private let didStop = Mutex(false)
    public var stopped: Bool { didStop.withLock { $0 } }

    public init(options: Options) { self.options = options }

    public func start(plan: RecordingPlan, movieURL: URL, events: @escaping @Sendable (RecordingEvent) -> Void) async throws {
        if options.failOnStart { throw RecordingSourceError.couldNotStart("fake failure") }
        let options = options
        let job = Task {
            let writer = try MasterWriter(url: movieURL, pixelSize: plan.pixelSize, fps: plan.fps)
            events(.started(hostTime: options.startHost))
            for i in 0..<Int(options.seconds * Double(plan.fps)) {
                let frame = try SyntheticFrames.solid(width: plan.pixelSize.width, height: plan.pixelSize.height, shade: UInt8(i % 200))
                try await writer.append(frame, at: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(plan.fps)))
            }
            try await writer.finish()
            if let reason = options.stopEvent { events(.stopped(reason)) }
        }
        task.withLock { $0 = job }
        // The real source reports .started after its first frame; wait for the writer to begin.
        try await Task.sleep(for: .milliseconds(1))
    }

    public func stop(atHostTime hostTime: Double) async throws -> RecordingResult {
        guard let job = task.withLock({ $0 }) else { throw RecordingSourceError.notRecording }
        didStop.withLock { $0 = true }
        try await job.value
        return RecordingResult(duration: options.seconds, startHost: options.startHost)
    }
}
