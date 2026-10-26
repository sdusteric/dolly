import AVFoundation
import Foundation
import Testing
@testable import DollyCore

@Suite struct MasterWriterTests {
    @Test func killedWriterLeavesPlayableFragment() async throws {
        let folder = tempURL("killed")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "take.mov")
        let writer = try MasterWriter(url: url, pixelSize: PixelSize(width: 320, height: 200), fps: 60)
        for i in 0..<(5 * 60) {
            try await writer.append(SyntheticFrames.solid(width: 320, height: 200, shade: UInt8(i % 255)),
                                    at: CMTime(value: CMTimeValue(i), timescale: 60))
        }
        try await Task.sleep(for: .milliseconds(300))
        // Never finished, as if Dolly was killed: a copy of the file must still play up to the last fragment.
        let copy = folder.appending(path: "copy.mov")
        try FileManager.default.copyItem(at: url, to: copy)
        let probe = await VideoProbe.probe(copy, countFrames: false)
        #expect(probe.playable)
        #expect(probe.durationSeconds >= 3.9)
        writer.abandon()
    }

    @Test func finishedWriterIsHEVCAtTheSize() async throws {
        let url = tempURL("done.mov")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try MasterWriter(url: url, pixelSize: PixelSize(width: 320, height: 200), fps: 60)
        for i in 0..<60 {
            try await writer.append(SyntheticFrames.solid(width: 320, height: 200, shade: 80), at: CMTime(value: CMTimeValue(i), timescale: 60))
        }
        try await writer.finish()
        let probe = await VideoProbe.probe(url)
        #expect(probe.codec == "hvc1" && probe.pixelSize == PixelSize(width: 320, height: 200))
        #expect(approx(probe.durationSeconds, 1.0, tol: 0.02))
    }
}
