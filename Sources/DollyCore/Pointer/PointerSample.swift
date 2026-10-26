import Foundation

public enum PointerShape: UInt8, Codable, Sendable {
    case arrow = 0, ibeam = 1, pointingHand = 2, other = 3
}

/// One pointer record (spec 4.3): host clock seconds, global points, the button bits (bit 0 left,
/// bit 1 right) and the pointer shape. 18 bytes on disk, little endian, in this field order.
public struct PointerSample: Hashable, Sendable {
    public static let byteCount = 18

    public var t: Double
    public var x: Float
    public var y: Float
    public var buttons: UInt8
    public var shape: PointerShape

    public init(t: Double, x: Float, y: Float, buttons: UInt8, shape: PointerShape) {
        self.t = t
        self.x = x
        self.y = y
        self.buttons = buttons
        self.shape = shape
    }

    public var leftDown: Bool { buttons & 1 != 0 }
}

/// The recorded window's frame in global points whenever it changes (spec 4.4). 24 bytes on disk.
public struct WindowFrameSample: Hashable, Sendable {
    public static let byteCount = 24

    public var t: Double
    public var frame: CGRect

    public init(t: Double, frame: CGRect) {
        self.t = t
        self.frame = frame
    }
}

/// Little-endian packing shared by both logs.
enum LogBytes {
    static func append(_ value: Double, to data: inout Data) {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
    }

    static func append(_ value: Float, to data: inout Data) {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
    }

    static func double(_ data: Data, _ offset: Int) -> Double {
        var raw: UInt64 = 0
        for i in 0..<8 { raw |= UInt64(data[data.startIndex + offset + i]) << (8 * i) }
        return Double(bitPattern: raw)
    }

    static func float(_ data: Data, _ offset: Int) -> Float {
        var raw: UInt32 = 0
        for i in 0..<4 { raw |= UInt32(data[data.startIndex + offset + i]) << (8 * i) }
        return Float(bitPattern: raw)
    }
}

/// Appends fixed-size records to a file. The caller flushes about once a second, so a killed
/// process loses at most the last second (plan Review Focus 1).
public final class RecordFileWriter {
    private let handle: FileHandle
    private var buffer = Data()

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: url)
    }

    func append(_ bytes: Data) { buffer.append(bytes) }

    public func flush() throws {
        guard !buffer.isEmpty else { return }
        try handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    public func close() throws {
        try flush()
        try handle.close()
    }
}
