import CoreGraphics
import DollyCore
import Foundation

nonisolated public enum TimelineHit: Hashable, Sendable {
    public enum StripPart: Hashable, Sendable { case body, startEdge, endEdge }
    public enum TrimEdge: Hashable, Sendable { case start, end }
    case strip(Zoom.ID, StripPart)
    case emptyZoomLane(Double)
    case trim(TrimEdge)
    case ruler(Double)
    case none
}

/// Where everything sits on the timeline's lanes (spec 6.3). x is measured from the start of the
/// track area (after the 64 pt lane names); y from the top of the ruler.
nonisolated public struct TimelineLayout: Sendable {
    public static let labelColumn: CGFloat = 64
    public static let ruler = CGRect(x: 0, y: 0, width: 0, height: 18)
    public static let videoLane = CGRect(x: 0, y: 26, width: 0, height: 56)
    public static let zoomLane = CGRect(x: 0, y: 88, width: 0, height: 46)
    public static let clickLane = CGRect(x: 0, y: 140, width: 0, height: 20)
    public static let height: CGFloat = 160
    public static let stripTop: CGFloat = 4
    public static let stripHeight: CGFloat = 22
    public static let edge: CGFloat = 6
    public static let trimGrab: CGFloat = 8

    public let width: CGFloat
    public let duration: Double

    public init(width: CGFloat, duration: Double) {
        self.width = max(width, 1)
        self.duration = max(duration, 0.001)
    }

    public func x(for t: Double) -> CGFloat { CGFloat(t / duration) * width }
    public func t(for x: CGFloat) -> Double { min(max(Double(x / width) * duration, 0), duration) }

    /// Every 5 s under a minute, 10 s under three, 30 s beyond.
    public var rulerTicks: [(x: CGFloat, label: String)] {
        let step: Double = duration < 60 ? 5 : duration < 180 ? 10 : 30
        return stride(from: 0, through: duration, by: step).map { (x(for: $0), TimeText.short($0)) }
    }

    public func strip(for zoom: Zoom) -> (frame: CGRect, inBand: CGRect, outBand: CGRect) {
        let frame = CGRect(x: x(for: zoom.start), y: Self.zoomLane.minY + Self.stripTop,
                           width: x(for: zoom.end) - x(for: zoom.start), height: Self.stripHeight)
        let inWidth = min(x(for: zoom.moveIn), frame.width), outWidth = min(x(for: zoom.moveOut), frame.width)
        return (frame, CGRect(x: frame.minX, y: frame.minY, width: inWidth, height: frame.height),
                CGRect(x: frame.maxX - outWidth, y: frame.minY, width: outWidth, height: frame.height))
    }

    public func hit(_ p: CGPoint, zooms: [Zoom], trim: ClosedRange<Double>? = nil) -> TimelineHit {
        if p.y >= Self.zoomLane.minY, p.y <= Self.zoomLane.maxY {
            for zoom in zooms {
                let f = strip(for: zoom).frame
                guard p.x >= f.minX, p.x <= f.maxX else { continue }
                if p.x - f.minX <= Self.edge { return .strip(zoom.id, .startEdge) }
                if f.maxX - p.x <= Self.edge { return .strip(zoom.id, .endEdge) }
                return .strip(zoom.id, .body)
            }
            return .emptyZoomLane(t(for: p.x))
        }
        if p.y >= Self.videoLane.minY, p.y <= Self.videoLane.maxY, let trim {
            if abs(p.x - x(for: trim.lowerBound)) <= Self.trimGrab { return .trim(.start) }
            if abs(p.x - x(for: trim.upperBound)) <= Self.trimGrab { return .trim(.end) }
        }
        if p.y >= 0, p.y <= Self.videoLane.maxY { return .ruler(t(for: p.x)) }
        return .none
    }
}

nonisolated public enum TimelineAccessibility {
    /// "Zoom 2 of 5, 0:07.3 to 0:09.9, 1.6 times, holds on Run check up" (spec 10.5).
    public static func label(_ zoom: Zoom, index: Int, count: Int) -> String {
        let what = zoom.mode == .hold ? "holds on \(zoom.name)" : "follows the pointer, \(zoom.name)"
        return "Zoom \(index + 1) of \(count), \(TimeText.clock(zoom.start)) to \(TimeText.clock(zoom.end)), "
            + String(format: "%.1f times, ", zoom.depth) + what
    }
}

nonisolated public enum TimelineHint {
    public static func text(clicks: Int, zooms: Int) -> String {
        let add = "Press Z to add a zoom at the playhead."
        guard clicks > 0 else { return "No clicks in this take. " + add }
        return "\(clicks) \(clicks == 1 ? "click" : "clicks") became \(zooms) \(zooms == 1 ? "zoom" : "zooms"). "
            + "Clicks less than 3 s apart share one zoom. " + add
    }
}
