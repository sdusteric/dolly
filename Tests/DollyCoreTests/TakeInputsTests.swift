import CoreGraphics
import Foundation
import Testing
@testable import DollyCore

@Suite struct TakeInputsTests {
    /// An area recorded at global (100, 50): a click at global (300, 250) is (200, 200) in the take.
    @Test func pointerPathUsesTheSavedRecordingRect() throws {
        let folder = tempURL("take")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let writer = try PointerLogWriter(url: folder.appending(path: TakeStore.pointerName))
        for s in makeLog(presses: [(down: 2.0, up: 2.1, x: 300, y: 250)], until: 5, rest: (300, 250)) { writer.append(s) }
        try writer.close()
        var take = Take(name: "Area", target: .area, size: CGSize(width: 640, height: 400), pixelScale: 2, fps: 60, duration: 5)
        take.recordingRect = CGRect(x: 100, y: 50, width: 640, height: 400)

        let path = try #require(TakeInputs.pointerPath(take: take, folder: folder))
        #expect(path.clicks.count == 1)
        #expect(approx(try #require(path.clicks.first).point, CGPoint(x: 200, y: 200)))
        #expect(approx(try #require(path.rawPosition(at: 4)), CGPoint(x: 200, y: 200)))
    }

    @Test func noPointerLogMeansNoPath() {
        let take = Take(name: "Area", target: .area, size: CGSize(width: 640, height: 400), pixelScale: 2, fps: 60, duration: 5)
        #expect(TakeInputs.pointerPath(take: take, folder: tempURL("missing")) == nil)
    }
}
