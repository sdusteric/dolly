import CoreGraphics
import Foundation

/// Maps global points (origin bottom-left of the main display) into recording points (origin
/// top-left of the recorded content, fixed size). A window that moves is followed through the
/// window log; one that is resized is scaled to fit the fixed size, as `scalesToFit` draws it.
public struct RecordingGeometry: Sendable {
    public let target: TargetKind
    public let recordingRect: CGRect
    public let windowFrames: [WindowFrameSample]
    public let size: CGSize

    public init(target: TargetKind, recordingRect: CGRect, windowFrames: [WindowFrameSample], size: CGSize) {
        self.target = target
        self.recordingRect = recordingRect
        self.windowFrames = windowFrames.sorted { $0.t < $1.t }
        self.size = size
    }

    /// The content's global rect at host time `t`.
    public func contentRect(at t: Double) -> CGRect {
        guard target == .window, let first = windowFrames.first else { return recordingRect }
        return windowFrames.last { $0.t <= t }?.frame ?? first.frame
    }

    public func toRecording(_ global: CGPoint, at t: Double) -> CGPoint? {
        let rect = contentRect(at: t)
        guard rect.width > 0, rect.height > 0,
              global.x >= rect.minX, global.x <= rect.maxX, global.y >= rect.minY, global.y <= rect.maxY else { return nil }
        let local = CGPoint(x: global.x - rect.minX, y: rect.maxY - global.y)
        let scale = min(size.width / rect.width, size.height / rect.height)
        let offset = CGPoint(x: (size.width - rect.width * scale) / 2, y: (size.height - rect.height * scale) / 2)
        return CGPoint(x: offset.x + local.x * scale, y: offset.y + local.y * scale)
    }
}
