import CoreGraphics
import CoreMedia
import Foundation
import Testing
@testable import DollyCore

/// A window take whose stop never wrote take.json: the movie, pointer log and window log are on
/// disk, as the 2026-11-04 takes were.
@Suite struct TakeRecoveryTests {
    let home = tempURL("recover")
    var store: TakeStore { TakeStore(paths: DollyPaths(environment: ["DOLLY_HOME": home.path(percentEncoded: false)])) }

    /// 2 s of movie at 2x a 160 x 100 pt window. The pointer log starts 0.3 s before the first frame
    /// and ends at the stop click on the menu bar, with one click on the window at 1.0 s.
    func makeBroken() async throws -> URL {
        let id = UUID()
        let folder = try store.createFolder(for: id)
        let writer = try MasterWriter(url: folder.appending(path: TakeStore.movieName), pixelSize: PixelSize(width: 320, height: 200), fps: 60)
        let frame = try SyntheticFrames.solid(width: 320, height: 200, shade: 90)
        for i in 0..<120 { try await writer.append(frame, at: CMTime(value: CMTimeValue(i), timescale: 60)) }
        try await writer.finish(endingAt: 2)
        let start = 1000.0, lead = 0.3
        let window = CGRect(x: 200, y: 300, width: 160, height: 100)
        let windows = try WindowFrameLogWriter(url: folder.appending(path: TakeStore.windowName))
        windows.append(WindowFrameSample(t: start - lead, frame: window))
        try windows.close()
        let pointer = try PointerLogWriter(url: folder.appending(path: TakeStore.pointerName))
        let log = makeLog(presses: [(lead + 1.0, lead + 1.08, 280, 350), (lead + 1.9, lead + 2.0, 1800, 1420)], until: lead + 2.0)
        log.forEach { pointer.append(PointerSample(t: start - lead + $0.t, x: $0.x, y: $0.y, buttons: $0.buttons, shape: $0.shape)) }
        try pointer.close()
        return folder
    }

    @Test func rebuildsAWindowTakeThatWasNeverSaved() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = try await makeBroken()
        let take = try await TakeRecovery.rebuild(folder, store: store)
        #expect(take.id.uuidString == folder.lastPathComponent)
        #expect(take.target == .window && take.size == CGSize(width: 160, height: 100) && take.pixelScale == 2)
        #expect(take.recordingRect == CGRect(x: 200, y: 300, width: 160, height: 100))
        #expect(abs(take.duration - 2) < 0.05)
        #expect(abs(take.recordingStartHost - 1000) < 0.05)
        // The click on the window makes a zoom near 1.0 s; the stop click on the menu bar makes none.
        let zoom = try #require(take.zooms.count == 1 ? take.zooms.first : nil)
        #expect(abs(zoom.start + ZoomRules().moveIn - 1.0) < 0.1)
        #expect(take.name == "Recovered take 1" && take.notes == [TakeRecovery.note])
        #expect(try store.load(folder) == take)
        if case .ok = store.list().first {} else { Issue.record("still listed as broken") }
    }

    @Test func leavesASavedTakeAlone() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = try await makeBroken()
        _ = try await TakeRecovery.rebuild(folder, store: store)
        await #expect(throws: TakeRecovery.Failure.alreadySaved) { try await TakeRecovery.rebuild(folder, store: store) }
    }

    @Test func refusesATakeWithoutItsWindowLog() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = try await makeBroken()
        try FileManager.default.removeItem(at: folder.appending(path: TakeStore.windowName))
        await #expect(throws: TakeRecovery.Failure.notAWindowTake) { try await TakeRecovery.rebuild(folder, store: store) }
    }
}
