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

    /// A take moved to the Trash while open is closed first, so switching away never writes it back.
    @Test func closingDropsTheOpenTakeWithoutSaving() throws {
        let (store, folderA, folderB) = try makeStore()
        let session = TakeSession(store: store)
        let a = try session.open(folder: folderA)
        a.renameTake("Edited")
        try FileManager.default.removeItem(at: folderA)
        session.close()
        #expect(session.editor == nil && session.folder == nil)
        try session.open(folder: folderB)
        #expect(!FileManager.default.fileExists(atPath: folderA.path(percentEncoded: false)))
    }

    @Test func saveWritesTheOpenTake() throws {
        let (store, folderA, _) = try makeStore()
        let session = TakeSession(store: store)
        let a = try session.open(folder: folderA)
        a.setDepth(try #require(a.take.zooms.first).id, 2.5)
        try session.save()
        #expect(try store.load(folderA).zooms.first?.depth == 2.5)
    }

    /// Review finding 5: a take whose picture is gone opens with the default color, so the Look tab
    /// shows what the clip shows.
    @Test func missingPictureOpensAsDefaultColor() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "dolly-session-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let store = TakeStore(paths: DollyPaths(environment: ["DOLLY_HOME": home.path]))
        var take = SyntheticTake.shelfDemo()
        take.look.background = .picture(file: "backdrop.jpg", blur: 4)
        let folder = try store.createFolder(for: take.id)
        try store.save(take)
        let editor = try TakeSession(store: store).open(folder: folder)
        #expect(editor.take.look.background == Look.defaultBackground)
        #expect(!editor.canUndo)
    }
}
