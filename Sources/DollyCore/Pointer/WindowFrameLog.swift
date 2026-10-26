import Foundation

public final class WindowFrameLogWriter {
    private let file: RecordFileWriter

    public init(url: URL) throws { file = try RecordFileWriter(url: url) }

    public func append(_ s: WindowFrameSample) {
        var d = Data(capacity: WindowFrameSample.byteCount)
        LogBytes.append(s.t, to: &d)
        for v in [s.frame.minX, s.frame.minY, s.frame.width, s.frame.height] { LogBytes.append(Float(v), to: &d) }
        file.append(d)
    }

    public func flush() throws { try file.flush() }
    public func close() throws { try file.close() }
}

/// `window.bin`: the recorded window's global frame each time it changes (spec 4.4).
public enum WindowFrameLog {
    public static func read(_ url: URL) throws -> [WindowFrameSample] {
        let data = try Data(contentsOf: url)
        let n = WindowFrameSample.byteCount
        return stride(from: 0, through: data.count - n, by: n).map { o in
            WindowFrameSample(t: LogBytes.double(data, o), frame: CGRect(
                x: Double(LogBytes.float(data, o + 8)), y: Double(LogBytes.float(data, o + 12)),
                width: Double(LogBytes.float(data, o + 16)), height: Double(LogBytes.float(data, o + 20))
            ))
        }
    }
}
