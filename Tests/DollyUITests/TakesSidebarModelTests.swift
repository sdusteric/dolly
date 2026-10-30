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
        var snapTake = Take(name: "Snap all-in-one toolbar", target: .window, size: CGSize(width: 800, height: 500), pixelScale: 2, fps: 60, duration: 36.0)
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

    @Test func brokenTakeRow() {
        let rows = TakesSidebarModel.rows(entries())
        #expect(rows.last?.title == "Can't open this take" && rows.last?.isBroken == true)
    }

    @Test func footerSaysWhereAndHowMuch() {
        #expect(TakesSidebarModel.footer(count: 4, bytes: 1_900_000_000) == "Takes live in ~/Movies/Dolly. 4 takes, 1.9 GB.")
        #expect(TakesSidebarModel.footer(count: 1, bytes: 52_000_000) == "Takes live in ~/Movies/Dolly. 1 take, 52 MB.")
        #expect(TakesSidebarModel.footer(count: 0, bytes: 0) == "Takes will live in ~/Movies/Dolly.")
    }

    @Test @MainActor func openingWithNoTakesGoesToRecord() {
        let screen = EditorScreenModel(entries: [], totalBytes: 0, editor: nil, recordShortcut: "⌃⌥⌘R")
        #expect(screen.opensToRecord)
        screen.entries = entries()
        #expect(!screen.opensToRecord)
        // A broken take still needs the editor, to show Show in Finder.
        screen.entries = [.broken(folder: URL(filePath: "/tmp/takes/y", directoryHint: .isDirectory), reason: "Can't open this take")]
        #expect(!screen.opensToRecord)
    }

    @Test func emptyStateCopy() {
        #expect(EmptyStateView.message == "Record a window, an area or the whole screen. Dolly zooms in where you click.")
    }
}
