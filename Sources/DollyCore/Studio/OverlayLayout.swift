import CoreGraphics
import Foundation

public enum CaptionPosition: String, Codable, Sendable, CaseIterable { case bottom, middle, top }

/// Where the camera bubble and the caption sit on one output canvas. Both are drawn in canvas space,
/// so neither zooms. Values are points at a 1080 px short side, scaled by `k`.
public struct OverlayLayout: Sendable {
    public static let marginFraction = 0.6
    public static let shrink = 0.6
    public static let border = 3.0
    public static let captionGap = 10.0

    public let canvas: CGSize
    public let recordingRect: CGRect
    public let camera: CameraTrack?
    public let captionPosition: CaptionPosition
    public let captionHeight: Double
    public let k: Double
    public let margin: Double

    /// `camera` is nil when the take has none or it is hidden at this time. `padding` is the look's,
    /// in points at 1080.
    public init(canvas: CGSize, recordingRect: CGRect, padding: Double, camera: CameraTrack?,
                captionPosition: CaptionPosition, captionHeight: Double) {
        self.canvas = canvas
        self.recordingRect = recordingRect
        self.camera = camera
        self.captionPosition = captionPosition
        self.captionHeight = captionHeight
        k = min(canvas.width, canvas.height) / 1080
        margin = Self.marginFraction * padding * k
    }

    /// The bubble in canvas pixels, top-left origin. `depthProgress` is 0 at 1x and 1 at a zoom's
    /// full depth; a shrinking bubble keeps its corner (or its center when dragged).
    public func bubble(at depthProgress: Double) -> CGRect? {
        guard let camera else { return nil }
        let full = min(max(camera.size, CameraTrack.sizeRange.lowerBound), CameraTrack.sizeRange.upperBound)
            * min(canvas.width, canvas.height)
        let p = camera.shrinkDuringZooms ? min(max(depthProgress, 0), 1) : 0
        let side = full * (1 - (1 - Self.shrink) * p)
        if let point = camera.point {
            let x = min(max(point.x * canvas.width, side / 2), canvas.width - side / 2)
            let y = min(max(point.y * canvas.height, side / 2), canvas.height - side / 2)
            return CGRect(x: x - side / 2, y: y - side / 2, width: side, height: side)
        }
        let left = camera.corner == .topLeft || camera.corner == .bottomLeft
        let top = camera.corner == .topLeft || camera.corner == .topRight
        return CGRect(x: left ? margin : canvas.width - margin - side,
                      y: top ? margin : canvas.height - margin - side, width: side, height: side)
    }

    /// The caption's box for art `width` pixels wide, centered across the canvas. A bottom caption
    /// moves above a bottom bubble it would cover (a top caption below a top one), measured at rest so
    /// the caption never moves during a zoom.
    public func captionRect(width: Double) -> CGRect {
        let w = min(width, canvas.width - 2 * margin), h = captionHeight
        let x = (canvas.width - w) / 2
        let gap = Self.captionGap * k
        func clashes(_ y: Double) -> CGRect? {
            guard let b = bubble(at: 0) else { return nil }
            let box = CGRect(x: x, y: y, width: w, height: h)
            return box.intersects(b.insetBy(dx: -gap, dy: -gap)) ? b : nil
        }
        switch captionPosition {
        case .middle:
            return CGRect(x: x, y: (canvas.height - h) / 2, width: w, height: h)
        case .bottom:
            var y = canvas.height - margin - h
            if let b = clashes(y), b.midY > canvas.height / 2 { y = max(0, b.minY - gap - h) }
            return CGRect(x: x, y: y, width: w, height: h)
        case .top:
            var y = margin
            if let b = clashes(y), b.midY < canvas.height / 2 { y = min(canvas.height - h, b.maxY + gap) }
            return CGRect(x: x, y: y, width: w, height: h)
        }
    }
}
