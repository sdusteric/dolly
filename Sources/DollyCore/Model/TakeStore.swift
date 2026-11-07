import Foundation

public enum TakeEntry: Hashable, Sendable {
    case ok(Take, folder: URL)
    case broken(folder: URL, reason: String)

    public var folder: URL {
        switch self {
        case .ok(_, let folder), .broken(let folder, _): folder
        }
    }
}

/// The takes folder is the database: one folder per take, named by its id (spec section 8).
public final class TakeStore: Sendable {
    public static let movieName = "take.mov"
    public static let pointerName = "pointer.bin"
    public static let windowName = "window.bin"
    public static let jsonName = "take.json"
    public static let posterName = "poster.jpg"
    public static let audioName = "audio.m4a"
    /// The sound other apps played, from ScreenCaptureKit, when System audio was on.
    public static let systemAudioName = "system.m4a"
    public static let brokenReason = "Can't open this take"

    public let paths: DollyPaths

    public init(paths: DollyPaths) {
        self.paths = paths
    }

    public func folder(for id: UUID) -> URL {
        paths.takesFolder.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    public func createFolder(for id: UUID) throws -> URL {
        let url = folder(for: id)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public func load(_ folder: URL) throws -> Take {
        let data = try Data(contentsOf: folder.appending(path: Self.jsonName))
        return try Self.decoder.decode(Take.self, from: data)
    }

    public func save(_ take: Take) throws {
        let data = try Self.encoder.encode(take)
        try AtomicFile.write(data, to: folder(for: take.id).appending(path: Self.jsonName))
    }

    /// Every take folder, newest first. Never throws: a folder that cannot be read is listed as
    /// broken so the sidebar can say so and offer Show in Finder.
    public func list() -> [TakeEntry] {
        let manager = FileManager.default
        let folders: [URL]
        do {
            folders = try manager.contentsOfDirectory(
                at: paths.takesFolder, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]
            ).filter(\.hasDirectoryPath)
        } catch {
            return []
        }
        var good: [(Take, URL)] = []
        var broken: [TakeEntry] = []
        for folder in folders {
            let movie = folder.appending(path: Self.movieName).path(percentEncoded: false)
            do {
                let take = try load(folder)
                if manager.fileExists(atPath: movie) {
                    good.append((take, folder))
                } else {
                    broken.append(.broken(folder: folder, reason: Self.brokenReason))
                }
            } catch {
                broken.append(.broken(folder: folder, reason: Self.brokenReason))
            }
        }
        let sorted = good.sorted { $0.0.created > $1.0.created }.map { TakeEntry.ok($0.0, folder: $0.1) }
        return sorted + broken.sorted { $0.folder.lastPathComponent < $1.folder.lastPathComponent }
    }

    /// Renames a take that is not open (the open one renames through its editor, for undo).
    /// A blank name is ignored.
    public func rename(_ folder: URL, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var take = try load(folder)
        take.name = trimmed
        try save(take)
    }

    public struct NotATakeFolder: Error, Sendable, Hashable {}

    /// Hands a take folder to `trash` (the Finder Trash in the app, so it can be put back). Refuses
    /// anything that is not a folder directly inside the takes folder. Exports stay where they are.
    public func moveToTrash(_ folder: URL, trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws {
        let takes = paths.takesFolder.standardizedFileURL.path(percentEncoded: false)
        let parent = folder.standardizedFileURL.deletingLastPathComponent().path(percentEncoded: false)
        guard parent.trimmingCharacters(in: ["/"]) == takes.trimmingCharacters(in: ["/"]) else { throw NotATakeFolder() }
        try trash(folder)
    }

    /// Bytes used by every take folder, for the sidebar footer.
    public func totalBytes() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: paths.takesFolder, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            do {
                total += Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            } catch {
                // A file that vanished mid-walk adds nothing to the footer's total.
            }
        }
        return total
    }

    /// Copies a picture into the take folder as `backdrop.<ext>` (then `backdrop 2.<ext>` and on), so
    /// the take still opens after the original moves. Older pictures stay, so undo can go back to
    /// them. Returns the new file name.
    public func importBackdrop(_ source: URL, into folder: URL) throws -> String {
        let ext = source.pathExtension.lowercased().isEmpty ? "jpg" : source.pathExtension.lowercased()
        let manager = FileManager.default
        let taken = Set(try manager.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).map { $0.lowercased() })
        var name = "backdrop.\(ext)"
        var n = 2
        while taken.contains(name) {
            name = "backdrop \(n).\(ext)"
            n += 1
        }
        let staged = folder.appending(path: ".backdrop-\(UUID().uuidString)")
        try manager.copyItem(at: source, to: staged)
        try manager.moveItem(at: staged, to: folder.appending(path: name))
        return name
    }

    /// "Use for new takes" with a picture: keeps a copy of it outside the take, so new takes can get
    /// their own. Returns the look to save as the default.
    public func saveDefaultBackdrop(_ look: Look, from folder: URL) throws -> Look {
        guard case .picture(let file, _) = look.background else { return look }
        let source = folder.appending(path: file)
        let target = paths.defaultBackdropURL(ext: source.pathExtension.lowercased())
        let manager = FileManager.default
        try manager.createDirectory(at: paths.supportFolder, withIntermediateDirectories: true)
        if manager.fileExists(atPath: target.path(percentEncoded: false)) { try manager.removeItem(at: target) }
        try manager.copyItem(at: source, to: target)
        return look
    }

    /// The default look for a new take in `folder`: its picture, if any, is copied in under a fresh
    /// name; with no saved picture the take gets the default color instead of a missing file.
    public func applyDefaultLook(_ look: Look, to folder: URL) throws -> Look {
        guard case .picture(let file, let blur) = look.background else { return look }
        var applied = look
        let saved = paths.defaultBackdropURL(ext: URL(filePath: file).pathExtension.lowercased())
        if FileManager.default.fileExists(atPath: saved.path(percentEncoded: false)) {
            applied.background = .picture(file: try importBackdrop(saved, into: folder), blur: blur)
        } else {
            applied.background = Look.defaultBackground
        }
        return applied
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
