import Foundation

public final class PointerLogWriter {
    private let file: RecordFileWriter

    public init(url: URL) throws { file = try RecordFileWriter(url: url) }

    public func append(_ s: PointerSample) {
        var d = Data(capacity: PointerSample.byteCount)
        LogBytes.append(s.t, to: &d)
        LogBytes.append(s.x, to: &d)
        LogBytes.append(s.y, to: &d)
        d.append(s.buttons)
        d.append(s.shape.rawValue)
        file.append(d)
    }

    public func flush() throws { try file.flush() }
    public func close() throws { try file.close() }
}

/// `pointer.bin` and its CSV form (`dollyctl pointer`, test fixtures).
public enum PointerLog {
    public static let csvHeader = "t,x,y,buttons,shape"

    /// Reads every whole record; a partial last record (a killed recording) is dropped.
    public static func read(_ url: URL) throws -> [PointerSample] {
        let data = try Data(contentsOf: url)
        let n = PointerSample.byteCount
        return stride(from: 0, through: data.count - n, by: n).map { o in
            PointerSample(
                t: LogBytes.double(data, o), x: LogBytes.float(data, o + 8), y: LogBytes.float(data, o + 12),
                buttons: data[data.startIndex + o + 16],
                shape: PointerShape(rawValue: data[data.startIndex + o + 17]) ?? .other
            )
        }
    }

    public static func csv(_ samples: [PointerSample]) -> String {
        ([csvHeader] + samples.map { "\($0.t),\($0.x),\($0.y),\($0.buttons),\($0.shape.rawValue)" })
            .joined(separator: "\n") + "\n"
    }

    public static func fromCSV(_ text: String) throws -> [PointerSample] {
        try text.split(whereSeparator: \.isNewline).dropFirst().map { line in
            let f = line.split(separator: ",")
            guard f.count == 5, let t = Double(f[0]), let x = Float(f[1]), let y = Float(f[2]),
                  let b = UInt8(f[3]), let s = UInt8(f[4]) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return PointerSample(t: t, x: x, y: y, buttons: b, shape: PointerShape(rawValue: s) ?? .other)
        }
    }
}
