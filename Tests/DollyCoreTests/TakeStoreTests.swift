import Foundation
import Testing
@testable import DollyCore

@Suite struct TakeStoreTests {
    let home: URL
    let paths: DollyPaths
    let store: TakeStore

    init() throws {
        home = FileManager.default.temporaryDirectory.appending(path: "dolly-store-\(UUID().uuidString)")
        paths = DollyPaths(environment: ["DOLLY_HOME": home.path])
        store = TakeStore(paths: paths)
    }

    private func makeMovie(in folder: URL) throws {
        try Data([0, 0, 0, 8]).write(to: folder.appending(path: TakeStore.movieName))
    }

    @Test func saveLoadRoundTrips() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        var take = SyntheticTake.shelfDemo()
        take.zooms = [Zoom(start: 1.8, end: 4.4, aim: CGPoint(x: 360, y: 225), depth: 1.6, mode: .hold,
                           moveIn: 0.6, moveOut: 0.5, source: .auto, clickIDs: [0], name: "Haul tile")]
        let folder = try store.createFolder(for: take.id)
        try makeMovie(in: folder)
        try store.save(take)
        #expect(try store.load(folder) == take)
    }

    @Test func listSkipsNothingAndMarksBroken() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let good = SyntheticTake.shelfDemo()
        try makeMovie(in: try store.createFolder(for: good.id))
        try store.save(good)

        let badJSON = try store.createFolder(for: UUID())
        try makeMovie(in: badJSON)
        try Data("{".utf8).write(to: badJSON.appending(path: TakeStore.jsonName))

        var noMovie = SyntheticTake.shelfDemo()
        noMovie.id = UUID()
        _ = try store.createFolder(for: noMovie.id)
        try store.save(noMovie)

        let entries = store.list()
        #expect(entries.count == 3)
        let broken = entries.filter { if case .broken = $0 { true } else { false } }
        #expect(broken.count == 2)
        #expect(broken.allSatisfy { if case .broken(_, let reason) = $0 { reason == "Can't open this take" } else { false } })
    }

    @Test func writesAreAtomic() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let take = SyntheticTake.shelfDemo()
        let folder = try store.createFolder(for: take.id)
        try store.save(take)
        try store.save(take)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.filter { $0.contains("tmp") }.isEmpty)
        let json = try String(contentsOf: folder.appending(path: TakeStore.jsonName), encoding: .utf8)
        #expect(json.contains("\"version\" : 1"))
    }

    @Test func listIsNewestFirst() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        var older = SyntheticTake.shelfDemo()
        older.created = Date(timeIntervalSince1970: 1_000)
        var newer = SyntheticTake.shelfDemo()
        newer.id = UUID()
        newer.created = Date(timeIntervalSince1970: 2_000)
        for take in [older, newer] {
            try makeMovie(in: try store.createFolder(for: take.id))
            try store.save(take)
        }
        let ids = store.list().compactMap { if case .ok(let t, _) = $0 { t.id } else { nil } }
        #expect(ids == [newer.id, older.id])
    }

    /// Review finding 6: each import gets its own name and older pictures stay, so undo can go back.
    @Test func importBackdropKeepsOlderForUndo() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = try store.createFolder(for: UUID())
        let a = home.appending(path: "a.PNG"), b = home.appending(path: "b.png")
        try Data([1]).write(to: a)
        try Data([2, 2]).write(to: b)
        let first = try store.importBackdrop(a, into: folder), second = try store.importBackdrop(b, into: folder)
        #expect(first.hasPrefix("backdrop") && first.hasSuffix(".png") && second.hasSuffix(".png") && first != second)
        #expect(try Data(contentsOf: folder.appending(path: first)) == Data([1]))
        #expect(try Data(contentsOf: folder.appending(path: second)) == Data([2, 2]))
    }

    /// Review finding 7: a default look with a picture brings its own copy into each new take.
    @Test func defaultPictureIsCopiedIntoNewTakes() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let source = try store.createFolder(for: UUID())
        try Data([7]).write(to: source.appending(path: "backdrop.jpg"))
        var look = Look()
        look.background = .picture(file: "backdrop.jpg", blur: 12)
        let saved = try store.saveDefaultBackdrop(look, from: source)
        let target = try store.createFolder(for: UUID())
        let applied = try store.applyDefaultLook(saved, to: target)
        guard case .picture(let file, let blur) = applied.background else { Issue.record("\(applied.background)"); return }
        let copied = try Data(contentsOf: target.appending(path: file))
        #expect(blur == 12 && copied == Data([7]))
        // Without a saved picture the new take gets the default color, never a missing file.
        try FileManager.default.removeItem(at: paths.defaultBackdropURL(ext: "jpg"))
        #expect(try store.applyDefaultLook(saved, to: target).background == Look.defaultBackground)
    }
}
