import CoreGraphics
import Foundation

/// Rebuilds take.json for a window take whose stop never saved it (Dolly quit or hung after the
/// movie was written). The movie gives the length and pixels, window.bin the window's frame, and
/// pointer.bin the clicks. The stop request is taken as the last pointer sample, which lands within
/// a few hundredths of a second of the stop click, so the first frame is that minus the length.
public enum TakeRecovery {
    public enum Failure: Error, Sendable, Hashable {
        case alreadySaved
        case notAWindowTake
        case missing(String)
        case unreadableMovie
    }

    public static let note = "Rebuilt after Dolly stopped before saving it"

    public static func rebuild(_ folder: URL, store: TakeStore, rules: ZoomRules = ZoomRules()) async throws -> Take {
        let manager = FileManager.default
        func exists(_ name: String) -> Bool { manager.fileExists(atPath: folder.appending(path: name).path(percentEncoded: false)) }
        guard !exists(TakeStore.jsonName) else { throw Failure.alreadySaved }
        guard let id = UUID(uuidString: folder.lastPathComponent) else { throw Failure.missing("a take id") }
        for name in [TakeStore.movieName, TakeStore.pointerName] where !exists(name) { throw Failure.missing(name) }
        guard exists(TakeStore.windowName) else { throw Failure.notAWindowTake }

        let movie = folder.appending(path: TakeStore.movieName)
        let probe = await VideoProbe.probe(movie, countFrames: false)
        guard probe.playable, probe.durationSeconds > 0, let pixels = probe.pixelSize else { throw Failure.unreadableMovie }
        let frames = try WindowFrameLog.read(folder.appending(path: TakeStore.windowName))
        guard let rect = frames.first?.frame, rect.width > 0 else { throw Failure.notAWindowTake }
        let samples = try PointerLog.read(folder.appending(path: TakeStore.pointerName))
        guard let stop = samples.map(\.t).max() else { throw Failure.missing("pointer samples") }

        let duration = probe.durationSeconds
        let start = stop - duration
        let used = Set(store.list().compactMap { entry -> String? in if case .ok(let take, _) = entry { take.name } else { nil } })
        let created = (try? manager.attributesOfItem(atPath: movie.path(percentEncoded: false))[.creationDate] as? Date) ?? Date()
        var n = 1
        while used.contains("Recovered take \(n)") { n += 1 }
        var take = Take(id: id, name: "Recovered take \(n)", created: created,
                        target: .window, size: rect.size, pixelScale: Double(pixels.width) / rect.width,
                        fps: 60, duration: duration, recordingStartHost: start, notes: [note])
        take.recordingRect = rect
        let geometry = RecordingGeometry(target: .window, recordingRect: rect, windowFrames: frames, size: rect.size)
        let clicks = ClickDetector.clicks(from: samples, geometry: geometry, recordingStartHost: start, stopRequestHost: stop)
        take.zooms = rules.zooms(for: clicks, size: rect.size, target: .window, trim: take.trim)
        try store.save(take)
        // As saved: take.json keeps whole seconds of the creation date.
        return try store.load(folder)
    }
}
