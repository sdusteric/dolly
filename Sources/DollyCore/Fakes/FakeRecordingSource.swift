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
        /// Writes a tone as system.m4a, starting 0.02 s after the first frame, when the plan asks.
        public var systemAudio: Bool
        /// Sends `stopEvent` before `start` returns, like a window that closes as capture begins.
        public var stopsWhileStarting: Bool
        public init(seconds: Double, failOnStart: Bool = false, startHost: Double = 0, stopEvent: RecordingStopReason? = nil,
                    systemAudio: Bool = false, stopsWhileStarting: Bool = false) {
            self.seconds = seconds
            self.failOnStart = failOnStart
            self.startHost = startHost
            self.stopEvent = stopEvent
            self.systemAudio = systemAudio
            self.stopsWhileStarting = stopsWhileStarting
        }
    }

    public let options: Options
    private let task = Mutex<Task<Void, any Error>?>(nil)
    private let didStop = Mutex(false)
    private let listeners = Mutex<[@Sendable (RecordingEvent) -> Void]>([])
    public var stopped: Bool { didStop.withLock { $0 } }

    public init(options: Options) { self.options = options }

    /// Sends `event` to the listener of the `index`th start, like a stream reporting late.
    public func send(_ event: RecordingEvent, toStart index: Int) {
        listeners.withLock { $0[index] }(event)
    }

    public func start(plan: RecordingPlan, movieURL: URL, events: @escaping @Sendable (RecordingEvent) -> Void) async throws {
        if options.failOnStart { throw RecordingSourceError.couldNotStart("fake failure") }
        let options = options
        listeners.withLock { $0.append(events) }
        let job = Task {
            let writer = try MasterWriter(url: movieURL, pixelSize: plan.pixelSize, fps: plan.fps)
            events(.started(hostTime: options.startHost))
            for i in 0..<Int(options.seconds * Double(plan.fps)) {
                let frame = try SyntheticFrames.solid(width: plan.pixelSize.width, height: plan.pixelSize.height, shade: UInt8(i % 200))
                try await writer.append(frame, at: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(plan.fps)))
            }
            try await writer.finish()
            if options.systemAudio, plan.systemAudio {
                try SyntheticTake.writeTone(to: movieURL.deletingLastPathComponent().appending(path: TakeStore.systemAudioName),
                                            seconds: options.seconds)
            }
            if let reason = options.stopEvent, !options.stopsWhileStarting { events(.stopped(reason)) }
        }
        task.withLock { $0 = job }
        if let reason = options.stopEvent, options.stopsWhileStarting { events(.stopped(reason)) }
        // The real source reports .started after its first frame; wait for the writer to begin.
        try await Task.sleep(for: .milliseconds(1))
    }

    public func stop(atHostTime hostTime: Double) async throws -> RecordingResult {
        guard let job = task.withLock({ $0 }) else { throw RecordingSourceError.notRecording }
        didStop.withLock { $0 = true }
        try await job.value
        return RecordingResult(duration: options.seconds, startHost: options.startHost,
                               systemAudioStart: options.systemAudio ? options.startHost + 0.02 : nil)
    }
}
