import CoreGraphics
import Foundation

/// The camera over time for one shape (spec 5.2), computed once from the zooms and sampled per
/// output frame by both the preview and the exporter.
public struct CameraPath: Sendable {
    public static let followRate = 120.0
    public static let deadZone = 0.6
    public static let followResponse = 0.4

    public let layout: ShapeLayout
    public let duration: Double
    private let zooms: [Zoom]
    /// The camera just before each zoom starts, so an overlapping zoom blends from what showed.
    private var from: [CameraState] = []
    /// Follow zooms: the camera center at 120 Hz from the zoom's start.
    private var tracks: [[CGPoint]] = []

    /// `pointer` gives the drawn pointer in recording points at a time, for follow zooms.
    public init(zooms: [Zoom], layout: ShapeLayout, pointer: (@Sendable (Double) -> CGPoint?)?, duration: Double) {
        self.layout = layout
        self.duration = duration
        self.zooms = zooms.sorted { $0.start < $1.start }
        tracks = self.zooms.map { Self.followTrack($0, layout: layout, pointer: pointer) }
        for i in self.zooms.indices {
            from.append(evaluate(self.zooms[i].start - 1e-6, upTo: i))
        }
    }

    public func camera(at t: Double) -> CameraState { evaluate(t, upTo: zooms.count) }

    private func evaluate(_ t: Double, upTo n: Int) -> CameraState {
        guard let i = zooms.indices.prefix(n).last(where: { zooms[$0].start <= t && t < zooms[$0].end }) else {
            return layout.rest
        }
        let z = zooms[i]
        let inEnd = z.start + z.moveIn, outStart = z.end - z.moveOut
        if t < inEnd {
            return from[i].lerp(to: held(i, inEnd), Easing.inOut((t - z.start) / max(z.moveIn, 1e-6)))
        }
        if t < outStart { return held(i, t) }
        return held(i, outStart).lerp(to: layout.rest, Easing.inOut((t - outStart) / max(z.moveOut, 1e-6)))
    }

    private func held(_ i: Int, _ t: Double) -> CameraState {
        let z = zooms[i]
        let track = tracks[i]
        guard z.mode == .follow, !track.isEmpty else {
            return CameraState(depth: z.depth, center: layout.canvasPoint(z.aim))
        }
        let index = min(max(Int(((t - z.start) * Self.followRate).rounded()), 0), track.count - 1)
        return CameraState(depth: z.depth, center: track[index])
    }

    /// The center moves only when the pointer leaves the middle 60% of the view, just far enough to
    /// put it back on the dead zone's edge, through a critically damped spring.
    private static func followTrack(_ z: Zoom, layout: ShapeLayout, pointer: (@Sendable (Double) -> CGPoint?)?) -> [CGPoint] {
        guard z.mode == .follow, let pointer else { return [] }
        let dt = 1 / followRate
        let half = CGSize(width: layout.canvas.width / z.depth * deadZone / 2,
                          height: layout.canvas.height / z.depth * deadZone / 2)
        let omega = 2 * Double.pi / followResponse
        var center = layout.canvasPoint(z.aim)
        var target = center
        var velocity = CGPoint.zero
        var out: [CGPoint] = []
        var t = z.start
        while t <= z.end + dt {
            if let p = pointer(t).map(layout.canvasPoint) {
                if p.x > target.x + half.width { target.x = p.x - half.width }
                if p.x < target.x - half.width { target.x = p.x + half.width }
                if p.y > target.y + half.height { target.y = p.y - half.height }
                if p.y < target.y - half.height { target.y = p.y + half.height }
            }
            velocity.x += (omega * omega * (target.x - center.x) - 2 * omega * velocity.x) * dt
            velocity.y += (omega * omega * (target.y - center.y) - 2 * omega * velocity.y) * dt
            center.x += velocity.x * dt
            center.y += velocity.y * dt
            out.append(center)
            t += dt
        }
        return out
    }
}
