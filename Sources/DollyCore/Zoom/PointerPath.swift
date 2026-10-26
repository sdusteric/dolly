import CoreGraphics
import Foundation

/// The pointer Dolly draws (spec 4.7), resampled at 120 Hz in recording points: smoothed by a
/// critically damped spring, pinned to the real point around each click, with a ring per click.
public struct PointerPath: Sendable {
    public static let rate = 120.0
    public static let response = 0.12
    public static let pin = 0.15
    public static let pinBlend = 0.1
    public static let ringLength = 0.36
    public static let stillAfter = 3.0
    public static let stillDistance = 1.0

    private let raw: [CGPoint?]
    private let drawn: [CGPoint?]
    private let shapes: [PointerShape]
    public let clicks: [Click]

    public init(samples: [PointerSample], geometry: RecordingGeometry, clicks: [Click], recordingStartHost: Double, look: Look) {
        self.clicks = clicks
        let sorted = samples.sorted { $0.t < $1.t }
        let end = (sorted.last?.t ?? recordingStartHost) - recordingStartHost
        let count = max(Int((end * Self.rate).rounded()) + 1, 0)
        var raw: [CGPoint?] = []
        var shapes: [PointerShape] = []
        var cursor = 0
        for i in 0..<count {
            let t = Double(i) / Self.rate
            while cursor + 1 < sorted.count, sorted[cursor + 1].t - recordingStartHost <= t + 1e-9 { cursor += 1 }
            guard let s = sorted.indices.contains(cursor) ? sorted[cursor] : nil else { break }
            raw.append(geometry.toRecording(CGPoint(x: Double(s.x), y: Double(s.y)), at: s.t))
            shapes.append(s.shape)
        }
        self.raw = raw
        self.shapes = shapes

        var drawn: [CGPoint?] = []
        var position: CGPoint?
        var velocity = CGPoint.zero
        var lastMove = 0.0
        var anchor: CGPoint?
        let omega = 2 * Double.pi / Self.response, dt = 1 / Self.rate
        for (i, point) in raw.enumerated() {
            let t = Double(i) / Self.rate
            guard let point else {
                drawn.append(nil)
                position = nil
                continue
            }
            if var p = position, look.smoothPointer {
                velocity.x += (omega * omega * (point.x - p.x) - 2 * omega * velocity.x) * dt
                velocity.y += (omega * omega * (point.y - p.y) - 2 * omega * velocity.y) * dt
                p.x += velocity.x * dt
                p.y += velocity.y * dt
                position = p
            } else {
                position = point
                velocity = .zero
            }
            var shown = position ?? point
            // Near a click the drawn pointer is the real one, so the click lands where it happened.
            if let near = clicks.map({ abs($0.t - t) }).min() {
                let w = min(max(1 - (near - Self.pin) / Self.pinBlend, 0), 1)
                shown = CGPoint(x: shown.x + (point.x - shown.x) * w, y: shown.y + (point.y - shown.y) * w)
            }
            if anchor.map({ hypot(point.x - $0.x, point.y - $0.y) > Self.stillDistance }) ?? true {
                anchor = point
                lastMove = t
            }
            drawn.append(look.hideWhenStill && t - lastMove > Self.stillAfter ? nil : shown)
        }
        self.drawn = drawn
    }

    private func index(_ t: Double) -> Int? {
        let i = Int((t * Self.rate).rounded())
        return drawn.indices.contains(i) ? i : nil
    }

    /// The drawn pointer in recording points, nil when it is off the recording or hidden.
    public func position(at t: Double) -> CGPoint? { index(t).flatMap { drawn[$0] } }

    /// The real logged position, for aiming a zoom added by hand.
    public func rawPosition(at t: Double) -> CGPoint? { index(t).flatMap { raw[$0] } }

    public func shape(at t: Double) -> PointerShape { index(t).map { shapes[$0] } ?? .arrow }

    public func ring(at t: Double) -> (center: CGPoint, progress: Double)? {
        guard let click = clicks.last(where: { t >= $0.t && t - $0.t < Self.ringLength }) else { return nil }
        return (click.point, (t - click.t) / Self.ringLength)
    }
}
