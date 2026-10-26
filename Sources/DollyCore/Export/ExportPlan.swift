import Foundation

/// One export of one take in one shape (spec 7).
public struct ExportPlan: Sendable, Hashable {
    public var take: Take
    public var shape: ShapePreset
    public var fps: Int
    public var bitRate: Int
    public var folder: URL

    public init(take: Take, shape: ShapePreset, fps: Int, bitRate: Int = 12_000_000, folder: URL) {
        self.take = take
        self.shape = shape
        self.fps = fps
        self.bitRate = bitRate
        self.folder = folder
    }

    /// `<take name> 16x9.mp4`, with `/` and `:` made safe, and ` 2`, ` 3` added when a file of
    /// that name already exists, so an export never overwrites.
    public func outputURL(existing: Set<String>) -> URL {
        var base = take.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = "Untitled take" }
        base += " \(shape.fileSuffix)"
        var name = base + ".mp4"
        var n = 2
        while existing.contains(name) {
            name = "\(base) \(n).mp4"
            n += 1
        }
        return folder.appending(path: name, directoryHint: .notDirectory)
    }
}
