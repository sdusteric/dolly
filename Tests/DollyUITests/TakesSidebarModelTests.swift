import CoreGraphics
import Foundation
import Testing
@testable import DollyCore
@testable import DollyUI

@Suite struct TakesSidebarModelTests {
    func entries() -> [TakeEntry] {
        var demo = SyntheticTake.shelfDemo()
        demo.zooms = (0..<5).map { i in
            Zoom(start: Double(i * 8), end: Double(i * 8 + 3), aim: .zero, depth: 1.6, mode: .hold, moveIn: 0.6, moveOut: 0.5,
                 source: .auto, clickIDs: [i], name: "z\(i)")
        }
        var snapTake = Take(name: "Still all-in-one toolbar", target: .window, size: CGSize(width: 800, height: 500), pixelScale: 2, fps: 60, duration: 36.0)
        snapTake.exports = [ExportRecord(shape: .wide16x9, url: URL(filePath: "/tmp/a.mp4"), date: Date())]
        let take1 = Take(name: "Shelf Tile Board, take 1", target: .window, size: CGSize(width: 848, height: 858), pixelScale: 2, fps: 60, duration: 72.6)
        let folder = URL(filePath: "/tmp/takes/x", directoryHint: .isDirectory)
        return [.ok(demo, folder: folder), .ok(take1, folder: folder), .ok(snapTake, folder: folder), .broken(folder: folder, reason: "Can't open this take")]
    }

    @Test func sidebarRowsReadLikeTheMockup() {
        let rows = TakesSidebarModel.rows(entries())
        #expect(rows[0].title == "Shelf Tile Board demo" && rows[0].meta == "0:48 · 5 zooms")
        #expect(rows[1].meta == "1:13 · 0 zooms")
        #expect(rows[2].meta == "0:36 · exported")
    }

    @Test func oneZoomIsSingular() {
        var take = SyntheticTake.shelfDemo()
        take.zooms = [Zoom(start: 1, end: 3, aim: .zero, depth: 2, mode: .hold, moveIn: 0.6, moveOut: 0.5, source: .auto, clickIDs: [], name: "")]
        #expect(TakesSidebarModel.rows([.ok(take, folder: URL(filePath: "/tmp"))])[0].meta == "0:48 · 1 zoom")
    }

    /// After a take goes to the Trash the editor opens the one below it, or the one above at the end.
    @Test func trashingOpensTheNeighbor() {
        let folders = (0..<3).map { URL(filePath: "/tmp/takes/\($0)", directoryHint: .isDirectory) }
        let entries: [TakeEntry] = folders.map { .ok(Take(name: $0.lastPathComponent, target: .window, size: CGSize(width: 10, height: 10),
                                                          pixelScale: 1, fps: 60, duration: 1), folder: $0) }
            + [.broken(folder: URL(filePath: "/tmp/takes/b"), reason: "Can't open this take")]
        #expect(TakesSidebarModel.neighbor(of: folders[1], in: entries)?.folder == folders[2])
        #expect(TakesSidebarModel.neighbor(of: folders[2], in: entries)?.folder == folders[1])
        #expect(TakesSidebarModel.neighbor(of: folders[0], in: Array(entries.prefix(1))) == nil)
    }

    /// A save changes only the open take, so the sidebar swaps that one entry and keeps the order.
    @Test func savingSwapsOnlyTheOpenTake() {
        let folders = (0..<3).map { URL(filePath: "/tmp/takes/\($0)", directoryHint: .isDirectory) }
        let takes = folders.map { Take(name: $0.lastPathComponent, target: .window, size: CGSize(width: 10, height: 10),
                                       pixelScale: 1, fps: 60, duration: 1) }
        let entries: [TakeEntry] = zip(takes, folders).map { .ok($0, folder: $1) }
            + [.broken(folder: URL(filePath: "/tmp/takes/b"), reason: "Can't open this take")]
        var saved = takes[1]
        saved.name = "Renamed"
        let patched = TakesSidebarModel.replacing(saved, at: URL(filePath: "/tmp/takes/1/", directoryHint: .isDirectory), in: entries)
        #expect(patched?.count == 4)
        #expect(patched?[1] == .ok(saved, folder: folders[1]))
        #expect(patched?[0] == entries[0] && patched?[2] == entries[2] && patched?[3] == entries[3])
        // A take the list does not have yet needs a full reload.
        #expect(TakesSidebarModel.replacing(saved, at: URL(filePath: "/tmp/takes/new"), in: entries) == nil)
    }

    @Test func brokenTakeRow() {
        let rows = TakesSidebarModel.rows(entries())
        #expect(rows.last?.title == "Can't open this take" && rows.last?.isBroken == true)
    }

    @Test func footerSaysWhereAndHowMuch() {
        #expect(TakesSidebarModel.footer(count: 4, bytes: 1_900_000_000) == "Takes live in ~/Movies/Dolly.\n4 takes, 1.9 GB.")
        #expect(TakesSidebarModel.footer(count: 1, bytes: 52_000_000) == "Takes live in ~/Movies/Dolly.\n1 take, 52 MB.")
        #expect(TakesSidebarModel.footer(count: 0, bytes: 0) == "Takes will live in ~/Movies/Dolly.")
    }

    @Test @MainActor func openingWithNoTakeOpenGoesToRecord() {
        let screen = EditorScreenModel(entries: [], totalBytes: 0, editor: nil, recordShortcut: "⌃⌥⌘R")
        #expect(screen.opensToRecord)
        // A fresh launch has takes on disk but none open: still the Record bar, not the last take.
        screen.entries = entries()
        #expect(screen.opensToRecord)
        // A take opened in this run comes back from the Dock.
        screen.editor = EditorModel(take: SyntheticTake.shelfDemo(), pointer: nil)
        #expect(!screen.opensToRecord)
    }

    @Test func emptyStateCopy() {
        #expect(EmptyStateView.message == "Record a window, an area or the whole screen. Dolly zooms in where you click.")
    }
}
