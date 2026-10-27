import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import DollyCore

@Suite struct ShelfStatusTests {
    let latest = ShelfLatest(title: "Shelf Tile Board demo", lengthSeconds: 48.2, exportedShapes: ["16:9"],
                             exportedAt: Date(timeIntervalSince1970: 1_800_000_000))

    func folder() throws -> URL {
        let url = tempURL("status")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func json(_ writer: ShelfStatusWriter) throws -> [String: Any] {
        let data = try Data(contentsOf: writer.statusFile)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func mode(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return try #require(attributes[.posixPermissions] as? Int)
    }

    func posterFile() throws -> URL {
        let url = tempURL("poster.jpg")
        let context = try #require(CGContext(data: nil, width: 480, height: 270, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0.31, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 480, height: 270))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    @Test func statusFileShape() throws {
        let writer = ShelfStatusWriter(directory: try folder(), appVersion: "0.1.0")
        try writer.write(latest: latest, poster: try posterFile(), showInShelf: false,
                         now: Date(timeIntervalSince1970: 1_800_000_100))
        let object = try json(writer)
        #expect(object["schema"] as? Int == 1)
        #expect(object["app"] as? String == "dolly")
        #expect(object["app_version"] as? String == "0.1.0")
        #expect(object["updated_at"] as? String == "2027-01-15T08:01:40Z")
        let entry = try #require(object["latest"] as? [String: Any])
        #expect(entry["title"] as? String == "Shelf Tile Board demo")
        #expect(entry["length_seconds"] as? Double == 48.2)
        #expect(entry["exported_shapes"] as? [String] == ["16:9"])
        #expect(entry["exported_at"] as? String == "2027-01-15T08:00:00Z")
        #expect(object["poster"] == nil)
        #expect(!FileManager.default.fileExists(atPath: writer.posterFile.path(percentEncoded: false)))
        #expect(try Data(contentsOf: writer.statusFile).count < ShelfStatusWriter.maxFileBytes)
        #expect(try mode(writer.statusFile) == 0o600)
    }

    @Test func posterOnlyWhenShowInShelfIsOn() throws {
        let writer = ShelfStatusWriter(directory: try folder(), appVersion: "0.1.0")
        let poster = try posterFile()
        try writer.write(latest: latest, poster: poster, showInShelf: true)
        #expect(try json(writer)["poster"] as? String == "dolly/poster.jpg")
        let data = try Data(contentsOf: writer.posterFile)
        #expect(data.count <= ShelfStatusWriter.maxPreviewBytes)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width <= ShelfStatusWriter.maxPreviewWidth)
        #expect(try mode(writer.posterFile) == 0o600)

        // Turning the setting off deletes the preview.
        try writer.write(latest: latest, poster: poster, showInShelf: false)
        #expect(try json(writer)["poster"] == nil)
        #expect(!FileManager.default.fileExists(atPath: writer.posterFile.path(percentEncoded: false)))
    }

    /// CONTRACT.md: titles are cut to 80 characters.
    @Test func longTitleIsCutTo80() throws {
        let writer = ShelfStatusWriter(directory: try folder(), appVersion: "0.1.0")
        var long = latest
        long.title = String(repeating: "a", count: 200)
        try writer.write(latest: long, poster: nil, showInShelf: false)
        let entry = try #require(try json(writer)["latest"] as? [String: Any])
        #expect((entry["title"] as? String)?.count == 80)
    }

    @Test func noLatestWritesCommonFieldsOnly() throws {
        let writer = ShelfStatusWriter(directory: try folder(), appVersion: "0.1.0")
        try writer.write(latest: nil, poster: nil, showInShelf: true)
        let object = try json(writer)
        #expect(object["latest"] == nil && object["poster"] == nil && object["app"] as? String == "dolly")
    }

    @Test func testHomeKeepsStatusInsideIt() {
        let paths = DollyPaths(environment: ["DOLLY_HOME": "/tmp/dolly-x"])
        #expect(paths.shelfStatusFolder.path(percentEncoded: false) == "/tmp/dolly-x/ShelfStatus/")
        let real = DollyPaths(environment: ["HOME": "/Users/o"])
        #expect(real.shelfStatusFolder.path(percentEncoded: false) == "/Users/o/Library/Application Support/Shelf/status/")
    }
}
