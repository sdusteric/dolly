import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The newest exported take, as Shelf shows it.
public struct ShelfLatest: Codable, Hashable, Sendable {
    public var title: String
    public var lengthSeconds: Double
    public var exportedShapes: [String]
    public var exportedAt: Date

    public init(title: String, lengthSeconds: Double, exportedShapes: [String], exportedAt: Date) {
        self.title = title
        self.lengthSeconds = lengthSeconds
        self.exportedShapes = exportedShapes
        self.exportedAt = exportedAt
    }

    enum CodingKeys: String, CodingKey {
        case title
        case lengthSeconds = "length_seconds"
        case exportedShapes = "exported_shapes"
        case exportedAt = "exported_at"
    }
}

/// The JSON Shelf reads: the common fields, `latest`, and `poster` while the preview exists.
struct ShelfStatusDocument: Codable, Equatable {
    var schema = 1
    var app = DollyURL.scheme
    var appVersion: String
    var updatedAt: Date
    var latest: ShelfLatest?
    var poster: String?

    enum CodingKeys: String, CodingKey {
        case schema, app, latest, poster
        case appVersion = "app_version"
        case updatedAt = "updated_at"
    }
}

/// Writes `dolly.json` and, only when "Show in Shelf" is on, `dolly/poster.jpg` into the Shelf
/// status folder (a port of Snap's writer). Each file goes to a temp name, is fsynced, then renamed.
public struct ShelfStatusWriter: Sendable {
    public static let maxFileBytes = 16 * 1024
    public static let maxPreviewWidth = 240
    public static let maxPreviewBytes = 30 * 1024
    public static let fileName = "dolly.json"
    public static let previewFolderName = "dolly"
    public static let posterName = "poster.jpg"
    /// CONTRACT.md: titles the owner sees in the app, cut to 80 characters.
    public static let maxTitleLength = 80

    public let directory: URL
    public let appVersion: String

    public init(directory: URL, appVersion: String) {
        self.directory = directory
        self.appVersion = appVersion
    }

    public var statusFile: URL { directory.appending(path: Self.fileName, directoryHint: .notDirectory) }
    public var previewDirectory: URL { directory.appending(path: Self.previewFolderName, directoryHint: .isDirectory) }
    public var posterFile: URL { previewDirectory.appending(path: Self.posterName, directoryHint: .notDirectory) }

    /// With `showInShelf` off no poster is written and any left over is deleted.
    public func write(latest: ShelfLatest?, poster: URL?, showInShelf: Bool, now: Date = Date()) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)

        var posterPath: String?
        if showInShelf, let poster, let data = Self.previewData(for: poster) {
            try manager.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
            try Self.writeAtomically(data, to: posterFile)
            posterPath = "\(Self.previewFolderName)/\(Self.posterName)"
        } else {
            removePoster()
        }

        var latest = latest
        if let title = latest?.title { latest?.title = String(title.prefix(Self.maxTitleLength)) }
        let document = ShelfStatusDocument(appVersion: appVersion, updatedAt: now, latest: latest, poster: posterPath)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)
        guard data.count <= Self.maxFileBytes else { throw POSIXError(.EFBIG) }
        try Self.writeAtomically(data, to: statusFile)
    }

    /// Deletes the poster and its folder.
    func removePoster() {
        let manager = FileManager.default
        if manager.fileExists(atPath: posterFile.path(percentEncoded: false)) {
            try? manager.removeItem(at: posterFile)
        }
        if (try? manager.contentsOfDirectory(atPath: previewDirectory.path(percentEncoded: false)))?.isEmpty == true {
            try? manager.removeItem(at: previewDirectory)
        }
    }

    /// A JPEG at most 240 px wide and 30 KB, or nil when the image cannot be read or made that small.
    static func previewData(for url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPreviewWidth,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        for quality in [0.7, 0.55, 0.4, 0.3, 0.2] {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            if CGImageDestinationFinalize(destination), data.length <= maxPreviewBytes { return data as Data }
        }
        return nil
    }

    /// Temp file next to the target (`.<name>.tmp`), mode 0600, fsync, then rename over the target.
    static func writeAtomically(_ data: Data, to url: URL) throws {
        let temp = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).tmp", directoryHint: .notDirectory)
        let tempPath = temp.path(percentEncoded: false)
        let descriptor = open(tempPath, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var failure: Int32 = 0
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    failure = errno
                    return
                }
                offset += written
            }
        }
        if failure == 0, fsync(descriptor) != 0 { failure = errno }
        if close(descriptor) != 0, failure == 0 { failure = errno }
        if failure == 0, fchmodat(AT_FDCWD, tempPath, 0o600, 0) != 0 { failure = errno }
        if failure == 0, rename(tempPath, url.path(percentEncoded: false)) != 0 { failure = errno }
        if failure != 0 {
            unlink(tempPath)
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
    }
}
