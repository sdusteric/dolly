import CoreGraphics
import DollyCore
import Foundation

nonisolated public enum TimelineHit: Hashable, Sendable {
    public enum StripPart: Hashable, Sendable { case body, startEdge, endEdge }
    public enum TrimEdge: Hashable, Sendable { case start, end }
    case strip(Zoom.ID, StripPart)
    case emptyZoomLane(Double)
    /// The camera lane where the camera shows, at a time.
    case cameraBar(Double)
    /// A hidden stretch of the camera, by index.
    case cameraGap(Int, StripPart)
    case caption(Caption.ID, StripPart)
    case emptyCaptionLane(Double)
    case speed(SpeedRegion.ID, StripPart)
    case emptySpeedLane(Double)
    case trim(TrimEdge)
    case ruler(Double)
    case none
}

/// Where everything sits on the timeline's lanes (spec 6.3). x is measured from the start of the
/// track area (after the 64 pt lane names); y from the top of the ruler.
nonisolated public struct TimelineLayout: Sendable {
    public static let labelColumn: CGFloat = 64
    public static let ruler = CGRect(x: 0, y: 0, width: 0, height: 18)
    public static let videoLane = CGRect(x: 0, y: 24, width: 0, height: 44)
    /// Cuts and speed-ups, under the video they change.
    public static let speedLane = CGRect(x: 0, y: 72, width: 0, height: 26)
    public static let zoomLane = CGRect(x: 0, y: 102, width: 0, height: 46)
    public static let cameraLane = CGRect(x: 0, y: 152, width: 0, height: 26)
    public static let captionLane = CGRect(x: 0, y: 182, width: 0, height: 30)
    public static let clickLane = CGRect(x: 0, y: 216, width: 0, height: 18)
    public static let height: CGFloat = 234
    /// The camera bar and caption chips sit 3 pt inside their lanes.
    public static let laneInset: CGFloat = 3
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

    public func chip(for caption: Caption) -> CGRect {
        CGRect(x: x(for: caption.start), y: Self.captionLane.minY + Self.laneInset,
               width: max(x(for: caption.end) - x(for: caption.start), 1), height: Self.captionLane.height - 2 * Self.laneInset)
    }

    public func speedRect(for region: SpeedRegion) -> CGRect {
        CGRect(x: x(for: region.start), y: Self.speedLane.minY + Self.laneInset,
               width: max(x(for: region.end) - x(for: region.start), 1), height: Self.speedLane.height - 2 * Self.laneInset)
    }

    /// Where the camera shows on its lane: the full width less the hidden stretches.
    public func cameraBars(_ camera: CameraTrack) -> [CGRect] {
        var bars: [CGRect] = []
        var from: Double = 0
        let y = Self.cameraLane.minY + Self.laneInset, h = Self.cameraLane.height - 2 * Self.laneInset
        for gap in camera.hidden.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if gap.lowerBound > from { bars.append(CGRect(x: x(for: from), y: y, width: x(for: gap.lowerBound) - x(for: from), height: h)) }
            from = max(from, gap.upperBound)
        }
        if from < duration { bars.append(CGRect(x: x(for: from), y: y, width: width - x(for: from), height: h)) }
        return bars
    }

    /// Which part of a span `p.x` falls on, with 6 pt edge zones like a zoom strip's.
    private func part(_ px: CGFloat, _ minX: CGFloat, _ maxX: CGFloat) -> TimelineHit.StripPart? {
        guard px >= minX, px <= maxX else { return nil }
        if px - minX <= Self.edge { return .startEdge }
        if maxX - px <= Self.edge { return .endEdge }
        return .body
    }

    public func hit(_ p: CGPoint, zooms: [Zoom], trim: ClosedRange<Double>? = nil, camera: CameraTrack? = nil,
                    captions: [Caption] = [], speeds: [SpeedRegion] = []) -> TimelineHit {
        if p.y >= Self.speedLane.minY, p.y <= Self.speedLane.maxY {
            for region in speeds {
                let r = speedRect(for: region)
                if let part = part(p.x, r.minX, r.maxX) { return .speed(region.id, part) }
            }
            return .emptySpeedLane(t(for: p.x))
        }
        if p.y >= Self.cameraLane.minY, p.y <= Self.cameraLane.maxY {
            guard let camera else { return .none }
            for (i, gap) in camera.hidden.enumerated() {
                if let part = part(p.x, x(for: gap.lowerBound), x(for: gap.upperBound)) { return .cameraGap(i, part) }
            }
            return .cameraBar(t(for: p.x))
        }
        if p.y >= Self.captionLane.minY, p.y <= Self.captionLane.maxY {
            for caption in captions {
                let c = chip(for: caption)
                if let part = part(p.x, c.minX, c.maxX) { return .caption(caption.id, part) }
            }
            return .emptyCaptionLane(t(for: p.x))
        }
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

extension TimelineAccessibility {
    /// "Cut 1 of 2, 0:03.0 to 0:05.0" or "4 times faster 1 of 2, ...".
    public static func label(_ region: SpeedRegion, index: Int, count: Int) -> String {
        let what = switch region.speed {
        case .cut: "Cut"
        case .fast(let rate): "\(Int(rate)) times faster"
        }
        return "\(what) \(index + 1) of \(count), \(TimeText.clock(region.start)) to \(TimeText.clock(region.end))"
    }

    /// "Caption 4 of 10, 0:11.4 to 0:14.6, Each tile has its own quick actions."
    public static func label(_ caption: Caption, index: Int, count: Int) -> String {
        "Caption \(index + 1) of \(count), \(TimeText.clock(caption.start)) to \(TimeText.clock(caption.end)), "
            + (caption.text.isEmpty ? "empty" : caption.text)
    }
}

nonisolated public enum TimelineHint {
    public static func text(clicks: Int, zooms: Int) -> String {
        let add = "Press Z to add a zoom, X to cut 2 seconds."
        guard clicks > 0 else { return "No clicks in this take. " + add }
        return "\(clicks) \(clicks == 1 ? "click" : "clicks") became \(zooms) \(zooms == 1 ? "zoom" : "zooms"). "
            + "Clicks less than 3 s apart share one zoom. " + add
    }
}
