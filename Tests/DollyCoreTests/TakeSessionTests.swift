import CoreGraphics
import Foundation
import Testing
@testable import DollyCore

@Suite struct TakeSessionTests {
    func makeStore() throws -> (TakeStore, URL, URL) {
        let store = TakeStore(paths: DollyPaths(environment: ["DOLLY_HOME": tempURL("home").path(percentEncoded: false)]))
        var a = Take(name: "A", target: .window, size: CGSize(width: 800, height: 600), pixelScale: 2, fps: 60, duration: 10)
        a.zooms = [Zoom(start: 2, end: 5, aim: CGPoint(x: 100, y: 100), depth: 2, mode: .hold, moveIn: 0.6, moveOut: 0.5,
                        source: .auto, clickIDs: [0], name: "Click")]
        let b = Take(name: "B", target: .window, size: CGSize(width: 800, height: 600), pixelScale: 2, fps: 60, duration: 10)
        let folderA = try store.createFolder(for: a.id)
        let folderB = try store.createFolder(for: b.id)
        try store.save(a)
        try store.save(b)
        return (store, folderA, folderB)
    }

    /// Review finding 1: a take reopened from the sidebar keeps the edits made before switching away.
    @Test func reopeningATakeShowsItsSavedEdits() throws {
        let (store, folderA, folderB) = try makeStore()
        let session = TakeSession(store: store)
        let a = try session.open(folder: folderA)
        let id = try #require(a.take.zooms.first).id
        a.move(id, by: 1)
        try session.open(folder: folderB)
        let again = try session.open(folder: folderA)
        #expect(again.take.zooms.first?.start == 3)
        #expect(try store.load(folderA).zooms.first?.start == 3)
    }

    @Test func saveWritesTheOpenTake() throws {
        let (store, folderA, _) = try makeStore()
        let session = TakeSession(store: store)
        let a = try session.open(folder: folderA)
        a.setDepth(try #require(a.take.zooms.first).id, 2.5)
        try session.save()
        #expect(try store.load(folderA).zooms.first?.depth == 2.5)
    }
}
