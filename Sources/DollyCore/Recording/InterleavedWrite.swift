import Foundation

/// One track being copied from a reader into a writer input: `next` reads a sample (nil at the
/// end), `append` hands it to the writer and returns false while the input is not ready.
public struct InterleavedStream<Sample> {
    public var next: () async throws -> Sample?
    public var time: (Sample) -> Double
    public var append: (Sample) throws -> Bool
    public var finish: () -> Void

    public init(next: @escaping () async throws -> Sample?, time: @escaping (Sample) -> Double,
                append: @escaping (Sample) throws -> Bool, finish: @escaping () -> Void) {
        self.next = next
        self.time = time
        self.append = append
        self.finish = finish
    }
}

/// Copies video and, if there is one, audio into a non-real-time writer. It reads whichever track
/// is behind first (the reader stalls when one output runs far ahead of the other), holds at most
/// one read sample per track, and when the writer refuses the sample it holds, reads ahead on the
/// other track instead of waiting. The writer can hold video back until more audio arrives (seen
/// under load, when its encoders lag), so waiting on one input alone could wait forever.
public enum InterleavedWrite {
    public static func run<Sample>(
        video: InterleavedStream<Sample>, audio: InterleavedStream<Sample>?, timeoutSeconds: Double = WriterInputAppend.timeoutSeconds,
        appended: (Sample, _ isVideo: Bool) -> Void = { _, _ in }
    ) async throws {
        var videoTrack = Track(stream: video)
        var audioTrack = audio.map { Track(stream: $0) }
        var lastProgress = DispatchTime.now().uptimeNanoseconds
        let timeout = UInt64(timeoutSeconds * 1_000_000_000)
        while !videoTrack.done || !(audioTrack?.done ?? true) {
            try Task.checkCancellation()
            var progressed = false
            let audioAt = audioTrack.flatMap { $0.done ? nil : $0.at } ?? .infinity
            if videoTrack.waiting, videoTrack.at <= audioAt {
                progressed = try await videoTrack.read()
            } else if audioTrack?.waiting == true {
                progressed = try await audioTrack!.read()
            }
            if let sample = videoTrack.held, try video.append(sample) {
                videoTrack.held = nil
                appended(sample, true)
                progressed = true
            }
            if let audio, let sample = audioTrack?.held, try audio.append(sample) {
                audioTrack?.held = nil
                appended(sample, false)
                progressed = true
            }
            if !progressed {
                // The writer refused what is held: read ahead on the track that has nothing in hand.
                if videoTrack.held != nil, audioTrack?.waiting == true {
                    progressed = try await audioTrack!.read()
                } else if audioTrack?.held != nil, videoTrack.waiting {
                    progressed = try await videoTrack.read()
                }
            }
            let now = DispatchTime.now().uptimeNanoseconds
            if progressed {
                lastProgress = now
            } else {
                guard now - lastProgress < timeout else { throw WriterInputAppend.TimedOut(seconds: timeoutSeconds) }
                try await Task.sleep(nanoseconds: WriterInputAppend.retryNanoseconds)
            }
        }
    }

    private struct Track<Sample> {
        let stream: InterleavedStream<Sample>
        var held: Sample?
        var at = -Double.infinity
        var done = false

        init(stream: InterleavedStream<Sample>) { self.stream = stream }

        /// Not finished and nothing in hand, so the next sample can be read.
        var waiting: Bool { !done && held == nil }

        /// Reads one sample into hand, or finishes the writer input at the end. Always progress.
        mutating func read() async throws -> Bool {
            if let sample = try await stream.next() {
                held = sample
                at = stream.time(sample)
            } else {
                stream.finish()
                done = true
            }
            return true
        }
    }
}
