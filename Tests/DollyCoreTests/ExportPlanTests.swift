import Foundation
import Testing
@testable import DollyCore

@Suite struct ExportPlanTests {
    func plan(_ name: String) -> ExportPlan {
        var take = SyntheticTake.shelfDemo()
        take.name = name
        return ExportPlan(take: take, shape: .wide16x9, fps: 60, folder: URL(filePath: "/tmp/out", directoryHint: .isDirectory))
    }

    @Test func sanitizesAndNumbersFileNames() {
        #expect(plan("Demo: v2/final").outputURL(existing: []).lastPathComponent == "Demo- v2-final 16x9.mp4")
        #expect(plan("Demo").outputURL(existing: ["Demo 16x9.mp4"]).lastPathComponent == "Demo 16x9 2.mp4")
        #expect(plan("Demo").outputURL(existing: ["Demo 16x9.mp4", "Demo 16x9 2.mp4"]).lastPathComponent == "Demo 16x9 3.mp4")
    }

    @Test func emptyNameStillGetsAFile() {
        #expect(plan("  ").outputURL(existing: []).lastPathComponent == "Untitled take 16x9.mp4")
    }

    @Test func defaults() {
        let p = plan("Demo")
        #expect(p.bitRate == 12_000_000 && p.fps == 60)
        #expect(p.outputURL(existing: []).deletingLastPathComponent().path == "/tmp/out")
    }
}
