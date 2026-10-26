import Foundation
import Testing
@testable import DollyCore

@Suite struct PointerLogTests {
    let samples = [
        PointerSample(t: 1.0, x: 10, y: 20, buttons: 0, shape: .arrow),
        PointerSample(t: 1.5, x: 11.5, y: 21.25, buttons: 1, shape: .ibeam),
        PointerSample(t: 2.0, x: 12, y: 22, buttons: 0, shape: .pointingHand),
    ]

    @Test func roundTripsBinary() throws {
        let url = tempURL("pointer.bin")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try PointerLogWriter(url: url)
        samples.forEach(writer.append)
        try writer.close()
        #expect(try PointerLog.read(url) == samples)
    }

    @Test func flushWritesWhatIsBuffered() throws {
        let url = tempURL("pointer.bin")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try PointerLogWriter(url: url)
        writer.append(samples[0])
        try writer.flush()
        #expect(try PointerLog.read(url) == [samples[0]])
        try writer.close()
    }

    @Test func truncatedLastRecordIsDropped() throws {
        let url = tempURL("pointer.bin")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try PointerLogWriter(url: url)
        samples.forEach(writer.append)
        try writer.close()
        let data = try Data(contentsOf: url)
        try data.dropLast(7).write(to: url)
        #expect(try PointerLog.read(url).count == 2)
    }

    @Test func csvRoundTrips() throws {
        #expect(try PointerLog.fromCSV(PointerLog.csv(samples)) == samples)
    }

    @Test func windowLogRoundTrips() throws {
        let url = tempURL("window.bin")
        defer { try? FileManager.default.removeItem(at: url) }
        let frames = [WindowFrameSample(t: 0, frame: CGRect(x: 0, y: 0, width: 848, height: 858)),
                      WindowFrameSample(t: 5, frame: CGRect(x: 200, y: 100, width: 848, height: 858))]
        let writer = try WindowFrameLogWriter(url: url)
        frames.forEach(writer.append)
        try writer.close()
        #expect(try WindowFrameLog.read(url) == frames)
    }

    @Test func shelfDemoFixtureLoads() throws {
        let s = try Fixtures.shelfDemoSamples()
        #expect(s.count > 5_000)
        #expect(approx(s.last!.t, 48.2, tol: 0.01))
    }
}
