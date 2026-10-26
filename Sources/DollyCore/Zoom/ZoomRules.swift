import CoreGraphics
import Foundation

/// Clicks to zooms (spec 5.1). Every number is a setting so the feel can be tuned on real demos.
public struct ZoomRules: Codable, Hashable, Sendable {
    public var groupGap = 3.0
    public var moveIn = 0.6
    public var hold = 1.5
    public var moveOut = 0.5
    public var mergeGap = 1.0
    public var singleDepth = 2.0
    public var spreadDepth = 1.8
    public var smallWindowDepth = 1.6
    public var smallWindowWidth = 900.0
    public var spreadFraction = 0.4
    public var minDepth = 1.25
    public var maxDepth = 3.0

    public init() {}

    public func zooms(for clicks: [Click], size: CGSize, target: TargetKind, trim: ClosedRange<Double>) -> [Zoom] {
        var groups: [[Click]] = []
        for click in clicks.sorted(by: { $0.t < $1.t }) {
            if let last = groups.last?.last, click.t - last.t < groupGap {
                groups[groups.count - 1].append(click)
            } else {
                groups.append([click])
            }
        }
        // Merge groups whose zooms would leave less than mergeGap between them.
        var merged: [[Click]] = []
        for group in groups {
            if let previous = merged.last,
               start(of: group) - end(of: previous) < mergeGap - 1e-9 {
                merged[merged.count - 1].append(contentsOf: group)
            } else {
                merged.append(group)
            }
        }
        return merged.compactMap { zoom(for: $0, size: size, target: target, trim: trim) }
    }

    private func start(of group: [Click]) -> Double { group[0].t - moveIn }
    private func end(of group: [Click]) -> Double { (group.last?.t ?? 0) + hold + moveOut }

    private func zoom(for group: [Click], size: CGSize, target: TargetKind, trim: ClosedRange<Double>) -> Zoom? {
        let xs = group.map(\.point.x), ys = group.map(\.point.y)
        let spread = max(((xs.max() ?? 0) - (xs.min() ?? 0)) / max(size.width, 1),
                         ((ys.max() ?? 0) - (ys.min() ?? 0)) / max(size.height, 1))
        let spreadOut = spread > spreadFraction
        let depth: Double
        if target == .window && size.width < smallWindowWidth {
            depth = smallWindowDepth
        } else if spreadOut {
            depth = spreadDepth
        } else {
            depth = singleDepth
        }
        let follow = spreadOut || group.contains(where: \.isDrag)
        let aim = follow
            ? CGPoint(x: xs.reduce(0, +) / Double(xs.count), y: ys.reduce(0, +) / Double(ys.count))
            : group[0].point
        let start = max(start(of: group), trim.lowerBound)
        let end = min(end(of: group), trim.upperBound)
        guard end > start else { return nil }
        return Zoom(
            start: start, end: end, aim: aim, depth: min(max(depth, minDepth), maxDepth),
            mode: follow ? .follow : .hold, moveIn: moveIn, moveOut: moveOut, source: .auto,
            clickIDs: group.map(\.id), name: "Click at \(TimeText.clock(group[0].t))"
        )
    }
}
