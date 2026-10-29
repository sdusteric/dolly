import CoreGraphics
import DollyCore
import Foundation

/// The geometry of Aim mode (spec 6.2): where a zoom's view sits on the stage and what a drag
/// inside it or on a corner does. The stage shows the take's shape scaled to `stageSize`.
nonisolated public struct AimOverlayModel: Sendable {
    public enum Corner: CaseIterable, Sendable { case topLeft, topRight, bottomLeft, bottomRight }

    public static let snapRadius = 12.0
    public static let hint = "Drag inside the corners to re-aim. Drag a corner to change depth."

    public let take: Take
    public let layout: ShapeLayout
    public let stageSize: CGSize
    private let clickPoints: [Int: CGPoint]

    public init(take: Take, clicks: [Click], stageSize: CGSize) {
        self.take = take
        layout = ShapeLayout(shape: take.currentShape, recordingSize: take.size, padding: take.look.padding)
        self.stageSize = stageSize
        clickPoints = Dictionary(clicks.map { ($0.id, $0.point) }, uniquingKeysWith: { a, _ in a })
    }

    /// Stage points per canvas pixel.
    public var stageScale: Double { stageSize.width / layout.canvas.width }
    /// Stage points per recording point.
    var pointScale: Double { stageScale * layout.scale }

    public func viewRect(for zoom: Zoom) -> CGRect {
        let r = layout.viewRect(CameraState(depth: zoom.depth, center: layout.canvasPoint(zoom.aim)))
        let s = stageScale
        return CGRect(x: r.minX * s, y: r.minY * s, width: r.width * s, height: r.height * s)
    }

    /// Where a recording point shows on the stage at 1x.
    public func stagePoint(_ recording: CGPoint) -> CGPoint {
        let p = layout.canvasPoint(recording)
        return CGPoint(x: p.x * stageScale, y: p.y * stageScale)
    }

    public func clickPoint(for zoom: Zoom) -> CGPoint? { zoom.clickIDs.first.flatMap { clickPoints[$0] } }

    /// The new aim after dragging inside the corners by `translation` stage points. Within 12 pt of
    /// the click that made the zoom it snaps back to the click, unless `snaps` is off (Shift).
    public func dragMove(_ zoom: Zoom, by translation: CGSize, snaps: Bool) -> CGPoint {
        var aim = CGPoint(x: zoom.aim.x + translation.width / pointScale, y: zoom.aim.y + translation.height / pointScale)
        aim.x = min(max(aim.x, 0), take.size.width)
        aim.y = min(max(aim.y, 0), take.size.height)
        if snaps, let click = clickPoint(for: zoom),
           hypot(aim.x - click.x, aim.y - click.y) * pointScale <= Self.snapRadius {
            return click
        }
        return aim
    }

    /// The new depth after dragging `corner` to `point`; the opposite corner stays put and the view
    /// keeps the stage's aspect, so the larger of the two spans decides.
    public func dragCorner(_ zoom: Zoom, _ corner: Corner, to point: CGPoint) -> Double {
        let opposite = Self.opposite(corner, of: viewRect(for: zoom))
        let width = max(abs(point.x - opposite.x), 1), height = max(abs(point.y - opposite.y), 1)
        let depth = min(stageSize.width / width, stageSize.height / height)
        return min(max(depth, EditorModel.depthRange.lowerBound), EditorModel.depthRange.upperBound)
    }

    /// The aim that keeps the opposite corner where it was at the new depth.
    public func aimKeeping(_ zoom: Zoom, _ corner: Corner, depth: Double) -> CGPoint {
        let opposite = Self.opposite(corner, of: viewRect(for: zoom))
        let w = stageSize.width / depth, h = stageSize.height / depth
        let center = CGPoint(x: opposite.x + (corner == .topLeft || corner == .bottomLeft ? -w / 2 : w / 2),
                             y: opposite.y + (corner == .topLeft || corner == .topRight ? -h / 2 : h / 2))
        let canvas = CGPoint(x: center.x / stageScale, y: center.y / stageScale)
        return CGPoint(x: min(max((canvas.x - layout.recordingRect.minX) / layout.scale, 0), take.size.width),
                       y: min(max((canvas.y - layout.recordingRect.minY) / layout.scale, 0), take.size.height))
    }

    public func label(for zoom: Zoom) -> String { String(format: "%.1f×  ", zoom.depth) + zoom.name }

    static func opposite(_ corner: Corner, of v: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: CGPoint(x: v.maxX, y: v.maxY)
        case .topRight: CGPoint(x: v.minX, y: v.maxY)
        case .bottomLeft: CGPoint(x: v.maxX, y: v.minY)
        case .bottomRight: CGPoint(x: v.minX, y: v.minY)
        }
    }
}
