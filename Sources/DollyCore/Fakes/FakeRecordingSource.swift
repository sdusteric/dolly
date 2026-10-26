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
        public init(seconds: Double, failOnStart: Bool = false, startHost: Double = 0) {
            self.seconds = seconds
            self.failOnStart = failOnStart
            self.startHost = startHost
        }
    }

    public let options: Options
    private let task = Mutex<Task<Void, any Error>?>(nil)

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
        }
        task.withLock { $0 = job }
        // The real source reports .started after its first frame; wait for the writer to begin.
        try await Task.sleep(for: .milliseconds(1))
    }

    public func stop() async throws -> RecordingResult {
        guard let job = task.withLock({ $0 }) else { throw RecordingSourceError.notRecording }
        try await job.value
        return RecordingResult(duration: options.seconds, startHost: options.startHost)
    }
}
