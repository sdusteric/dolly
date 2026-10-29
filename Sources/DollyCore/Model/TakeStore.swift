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

    /// Copies a picture into the take folder as `backdrop.<ext>`, so the take still opens after the
    /// original moves, and removes any older backdrop. Returns the new file name.
    public func importBackdrop(_ source: URL, into folder: URL) throws -> String {
        let ext = source.pathExtension.lowercased()
        let name = "backdrop." + (ext.isEmpty ? "jpg" : ext)
        let manager = FileManager.default
        let staged = folder.appending(path: ".backdrop-\(UUID().uuidString)")
        try manager.copyItem(at: source, to: staged)
        for old in try manager.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) where old.hasPrefix("backdrop.") {
            try manager.removeItem(at: folder.appending(path: old))
        }
        try manager.moveItem(at: staged, to: folder.appending(path: name))
        return name
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
