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

    @Test func importBackdropReplacesOld() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = try store.createFolder(for: UUID())
        let a = home.appending(path: "a.PNG"), b = home.appending(path: "b.jpg")
        try Data([1]).write(to: a)
        try Data([2, 2]).write(to: b)
        #expect(try store.importBackdrop(a, into: folder) == "backdrop.png")
        #expect(try store.importBackdrop(b, into: folder) == "backdrop.jpg")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("backdrop") }
        #expect(names == ["backdrop.jpg"])
        #expect(try Data(contentsOf: folder.appending(path: "backdrop.jpg")) == Data([2, 2]))
    }
}
