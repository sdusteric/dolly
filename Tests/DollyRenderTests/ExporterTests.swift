import AVFoundation
import Foundation
import Testing
@testable import DollyCore
@testable import DollyRender

/// The four-character names of an mp4's top-level boxes, in file order.
func topLevelAtoms(_ url: URL) throws -> [String] {
    let data = try Data(contentsOf: url)
    var out: [String] = []
    var offset = 0
    while offset + 8 <= data.count {
        var size = Int(data[offset..<offset + 4].reduce(0) { $0 << 8 | UInt64($1) })
        out.append(String(decoding: data[offset + 4..<offset + 8], as: UTF8.self))
        if size == 1, offset + 16 <= data.count { size = Int(data[offset + 8..<offset + 16].reduce(0) { $0 << 8 | UInt64($1) }) }
        guard size >= 8 else { break }
        offset += size
    }
    return out
}

@Suite struct ExporterTests {
    func fixture() async throws -> (Take, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "dolly-export-\(UUID().uuidString)")
        let folder = root.appending(path: "take"), out = root.appending(path: "out")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await SyntheticTake.writeMovie(seconds: 3, fps: 60, variableRate: true, to: folder.appending(path: TakeStore.movieName))
        var take = Take(name: "Demo: v2", target: .display, size: CGSize(width: 1440, height: 900), pixelScale: 1, fps: 60, duration: 3)
        take.zooms = [Zoom(start: 0.5, end: 2.5, aim: CGPoint(x: 300, y: 450), depth: 2, mode: .hold, moveIn: 0.6, moveOut: 0.5,
                           source: .manual, clickIDs: [], name: "x")]
        return (take, folder, out)
    }

    @Test func exportsFastStart1080p60() async throws {
        let (take, folder, out) = try await fixture()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let url = try await Exporter().export(ExportPlan(take: take, shape: .wide16x9, fps: 60, folder: out), takeFolder: folder,
                                              pointer: nil, progress: { _ in })
        #expect(url.lastPathComponent == "Demo- v2 16x9.mp4")
        let p = await VideoProbe.probe(url)
        #expect(p.pixelSize == PixelSize(width: 1920, height: 1080) && p.codec == "avc1")
        #expect(abs((p.nominalFrameRate ?? 0) - 60) < 0.5)
        #expect(abs(p.durationSeconds - 3.0) <= 1.0 / 60 + 0.001)
        let atoms = try topLevelAtoms(url)
        #expect(try #require(atoms.firstIndex(of: "moov")) < (try #require(atoms.firstIndex(of: "mdat"))))
    }

    @Test func exportHonorsTrim() async throws {
        var (take, folder, out) = try await fixture()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        take.trim = 0.5...2.5
        let url = try await Exporter().export(ExportPlan(take: take, shape: .wide16x9, fps: 30, folder: out), takeFolder: folder,
                                              pointer: nil, progress: { _ in })
        #expect(abs(await VideoProbe.probe(url).durationSeconds - 2.0) <= 1.0 / 30 + 0.001)
    }

    @Test func neverOverwritesAndReportsProgress() async throws {
        let (take, folder, out) = try await fixture()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let plan = ExportPlan(take: take, shape: .wide16x9, fps: 30, folder: out)
        let progress = ProgressLog()
        let first = try await Exporter().export(plan, takeFolder: folder, pointer: nil, progress: { progress.add($0) })
        let second = try await Exporter().export(plan, takeFolder: folder, pointer: nil, progress: { _ in })
        #expect(first != second && second.lastPathComponent == "Demo- v2 16x9 2.mp4")
        #expect(progress.values.last == 1.0 && progress.values.count > 3)
        let names = try FileManager.default.contentsOfDirectory(atPath: out.path)
        #expect(names.filter { $0.hasPrefix(".") }.isEmpty)
    }

    @Test func cancelLeavesNoFile() async throws {
        let (take, folder, out) = try await fixture()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let job = Task { try await Exporter().export(ExportPlan(take: take, shape: .wide16x9, fps: 60, folder: out), takeFolder: folder,
                                                     pointer: nil, progress: { _ in }) }
        job.cancel()
        await #expect(throws: CancellationError.self) { try await job.value }
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: out.path)) ?? []).isEmpty)
    }

    /// A quit or crash mid-export leaves the hidden scratch folder; the next launch removes it
    /// and nothing else.
    @Test func sweepRemovesOnlyScratchFolders() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "dolly-sweep-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let scratch = root.appending(path: "\(Exporter.scratchPrefix)1234")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try Data([1]).write(to: scratch.appending(path: "export.mp4"))
        try Data([1]).write(to: root.appending(path: "Demo 16x9.mp4"))
        try FileManager.default.createDirectory(at: root.appending(path: ".other"), withIntermediateDirectories: true)
        Exporter.sweepScratch(in: root)
        let left = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        #expect(left == [".other", "Demo 16x9.mp4"])
    }

    @Test func posterIsAJPEG480Wide() async throws {
        let (_, folder, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let url = folder.appending(path: TakeStore.posterName)
        try await PosterMaker.poster(movie: folder.appending(path: TakeStore.movieName), at: 0.5, to: url)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 480)
        #expect(CGImageSourceGetType(source) as String? == "public.jpeg")
    }
}

final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Double] = []
    func add(_ v: Double) { lock.withLock { stored.append(v) } }
    var values: [Double] { lock.withLock { stored } }
}
