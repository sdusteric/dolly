import CoreGraphics
import Foundation

/// What dollyctl prints, kept here so the commands are tested without running the binary.
public enum DollyctlCommands {
    /// One line per zoom: start, end, depth, mode, aim and name.
    public static func zoomLines(samples: [PointerSample], size: CGSize, target: TargetKind) -> [String] {
        let rect = CGRect(origin: .zero, size: size)
        let geometry = RecordingGeometry(target: target, recordingRect: rect,
                                         windowFrames: target == .window ? [WindowFrameSample(t: 0, frame: rect)] : [],
                                         size: size)
        let end = samples.last?.t ?? 0
        let clicks = ClickDetector.clicks(from: samples, geometry: geometry, recordingStartHost: 0, stopRequestHost: end)
        return ZoomRules().zooms(for: clicks, size: size, target: target, trim: 0...end).map(zoomLine)
    }

    public static func zoomLine(_ zoom: Zoom) -> String {
        "\(one(zoom.start)) \(one(zoom.end)) \(one(zoom.depth))x \(zoom.mode.rawValue) "
            + "(\(Int(zoom.aim.x.rounded())), \(Int(zoom.aim.y.rounded()))) \(zoom.name)"
    }

    /// The 16:9 camera at `t`: time, depth and center in canvas points.
    public static func cameraLine(take: Take, pointer: PointerPath?, at t: Double) -> String {
        let layout = ShapeLayout(shape: .wide16x9, recordingSize: take.size, padding: take.look.padding)
        let path = CameraPath(zooms: take.zooms, layout: layout,
                              pointer: pointer.map { p in { @Sendable t in p.position(at: t) } }, duration: take.duration)
        let camera = path.camera(at: t)
        return "\(one(t)) \(String(format: "%.2f", camera.depth))x "
            + "(\(Int(camera.center.x.rounded())), \(Int(camera.center.y.rounded())))"
    }

    public static func parseSize(_ text: String) -> CGSize? {
        let parts = text.lowercased().split(separator: "x")
        guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]), w > 0, h > 0 else { return nil }
        return CGSize(width: w, height: h)
    }

    public static func parseTimes(_ text: String) -> [Double]? {
        let values = text.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard !values.isEmpty, values.allSatisfy({ $0 != nil }) else { return nil }
        return values.compactMap(\.self)
    }

    public struct UsageError: Error, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// `original`, `16x9`, `1x1`, `4x5` or `9x16`.
    public static func parseShape(_ text: String) throws -> ShapePreset {
        guard let shape = ShapePreset.allCases.first(where: { $0.fileSuffix == text.lowercased() }) else {
            throw UsageError(message: "unknown shape \(text); use " + ShapePreset.allCases.map(\.fileSuffix).joined(separator: ", "))
        }
        return shape
    }

    /// The take's captions as the .srt an export would write, or nothing when it has none.
    public static func captionsSRT(_ take: Take) -> String {
        let items = (take.captions?.items ?? []).filter { $0.start < take.trim.upperBound && !$0.text.isEmpty }
        return items.isEmpty ? "" : SRT.text(items, trimStart: take.trim.lowerBound)
    }

    private static func one(_ v: Double) -> String { String(format: "%.1f", v) }
}
