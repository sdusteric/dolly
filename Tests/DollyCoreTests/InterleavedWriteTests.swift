import Foundation
import Testing
@testable import DollyCore

/// A stand-in for AVAssetWriter's muxer: it takes a video frame only once the audio written so far
/// reaches half a second past it, as the real writer did when its audio encoder held data back.
private final class FakeMux {
    var video: [Double] = stride(from: 0.0, to: 3, by: 1.0 / 30).map { $0 }
    var audio: [Double] = stride(from: 0.0, to: 3, by: 0.2).map { $0 }
    var audioReach = -Double.infinity
    var audioFinished = false
    var videoWritten: [Double] = []
    var audioWritten: [Double] = []
    var finished: Set<String> = []

    func streams() -> (InterleavedStream<Double>, InterleavedStream<Double>) {
        let video = InterleavedStream<Double>(
            next: { self.video.isEmpty ? nil : self.video.removeFirst() },
            time: { $0 },
            append: { t in
                guard self.audioFinished || self.audioReach >= t + 0.5 else { return false }
                self.videoWritten.append(t)
                return true
            },
            finish: { self.finished.insert("video") })
        let audio = InterleavedStream<Double>(
            next: { self.audio.isEmpty ? nil : self.audio.removeFirst() },
            time: { $0 },
            append: { t in
                self.audioWritten.append(t)
                self.audioReach = t + 0.2
                return true
            },
            finish: {
                self.audioFinished = true
                self.finished.insert("audio")
            })
        return (video, audio)
    }
}

@Suite struct InterleavedWriteTests {
    @Test func feedsAudioAheadWhenTheWriterHoldsVideoBack() async throws {
        let mux = FakeMux()
        let (video, audio) = mux.streams()
        try await InterleavedWrite.run(video: video, audio: audio, timeoutSeconds: 1)
        #expect(mux.videoWritten.count == 90)
        #expect(mux.audioWritten.count == 15)
        #expect(mux.finished == ["video", "audio"])
    }

    @Test func videoAloneIsWrittenInOrder() async throws {
        let mux = FakeMux()
        mux.audioFinished = true
        let (video, _) = mux.streams()
        var count = 0
        try await InterleavedWrite.run(video: video, audio: nil, timeoutSeconds: 1) { _, isVideo in if isVideo { count += 1 } }
        #expect(mux.videoWritten == mux.videoWritten.sorted() && mux.videoWritten.count == 90 && count == 90)
    }

    @Test func aWriterThatNeverTakesDataTimesOut() async {
        let stuck = InterleavedStream<Double>(next: { 0 }, time: { $0 }, append: { _ in false }, finish: {})
        await #expect(throws: (any Error).self) { try await InterleavedWrite.run(video: stuck, audio: nil, timeoutSeconds: 0.2) }
    }
}
