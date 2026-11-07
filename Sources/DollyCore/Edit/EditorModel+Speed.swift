import Foundation

/// Cuts and speed-ups (spec 6.3.1). Regions stay inside the trim, sorted, at least
/// `speedMinimum` long, never overlap, and never leave less than `clipMinimum` of clip.
extension EditorModel {
    public static let speedMinimum = 0.2
    public static let clipMinimum = 0.5
    public static let addedCut = 2.0

    public func speedRegion(_ id: SpeedRegion.ID) -> SpeedRegion? { take.speedRegions.first { $0.id == id } }

    public var selectedSpeed: SpeedRegion.ID? {
        if case .speed(let id) = selection { id } else { nil }
    }

    /// X: a 2 s cut from the playhead, stopped by the trim or the next region.
    public func addCut(at t: Double) {
        guard !take.speedRegions.contains(where: { t >= $0.start && t < $0.end }) else { return }
        addSpeed(from: t, to: t + Self.addedCut, speed: .cut)
    }

    /// A drag on the Speed lane, or X. It stops at the trim and at the regions on either side.
    public func addSpeed(from t0: Double, to t1: Double, speed: SpeedRegion.Speed) {
        let anchor = min(max(t0, take.trim.lowerBound), take.trim.upperBound)
        guard !take.speedRegions.contains(where: { anchor >= $0.start && anchor < $0.end }) else { return }
        let (lo, hi) = room(around: anchor, excluding: nil)
        let start = max(min(t0, t1), lo), end = min(max(t0, t1), hi)
        guard end - start >= Self.speedMinimum - 1e-9 else { return }
        let region = SpeedRegion(start: start, end: end, speed: speed)
        guard leavesEnoughClip(adding: region) else { return }
        change { $0.speedRegions.append(region) }
        selection = .speed(region.id)
    }

    public func setSpeed(_ id: SpeedRegion.ID, _ speed: SpeedRegion.Speed) {
        guard let region = speedRegion(id) else { return }
        var next = region
        next.speed = speed
        guard leavesEnoughClip(replacing: region, with: next) else { return }
        editSpeed(id) { r, _, _ in r.speed = speed }
    }

    public func resizeSpeed(_ id: SpeedRegion.ID, edge: Edge, to t: Double) {
        editSpeed(id) { r, lo, hi in
            switch edge {
            case .start: r.start = min(max(t, lo), r.end - Self.speedMinimum)
            case .end: r.end = max(min(t, hi), r.start + Self.speedMinimum)
            }
        }
    }

    public func moveSpeed(_ id: SpeedRegion.ID, by dt: Double) {
        editSpeed(id) { r, lo, hi in
            let length = r.length
            r.start = min(max(r.start + dt, lo), hi - length)
            r.end = r.start + length
        }
    }

    public func removeSpeed(_ id: SpeedRegion.ID) {
        guard speedRegion(id) != nil else { return }
        change { $0.speedRegions.removeAll { $0.id == id } }
        if selectedSpeed == id { selection = nil }
    }

    /// Delete: whatever is selected on the timeline.
    public func removeSelected() {
        switch selection {
        case .zoom(let id): remove(id)
        case .caption(let id): removeCaption(id)
        case .speed(let id): removeSpeed(id)
        case .camera, nil: break
        }
    }

    // MARK: Helpers

    /// The free stretch around `t`: from the end of the region before to the start of the one after.
    private func room(around t: Double, excluding id: SpeedRegion.ID?) -> (Double, Double) {
        let others = take.speedRegions.filter { $0.id != id }
        let lo = others.filter { $0.end <= t + 1e-9 }.map(\.end).max() ?? take.trim.lowerBound
        let hi = others.filter { $0.start >= t - 1e-9 }.map(\.start).min() ?? take.trim.upperBound
        return (max(lo, take.trim.lowerBound), min(hi, take.trim.upperBound))
    }

    private func leavesEnoughClip(adding region: SpeedRegion) -> Bool {
        var next = take
        next.speedRegions.append(region)
        return next.outputDuration >= Self.clipMinimum && next.timeMap.pieces.count > 0
            && !(region.speed == .cut && next.outputDuration > take.outputDuration - 1e-9)
    }

    private func leavesEnoughClip(replacing old: SpeedRegion, with new: SpeedRegion) -> Bool {
        var next = take
        next.speedRegions = next.speedRegions.map { $0.id == old.id ? new : $0 }
        return TimeMap(trim: next.trim, regions: next.speedRegions).duration >= Self.clipMinimum
    }

    /// Runs `body` on one region with the bounds its neighbors and the trim leave it.
    private func editSpeed(_ id: SpeedRegion.ID, _ body: @escaping (inout SpeedRegion, Double, Double) -> Void) {
        guard let region = speedRegion(id) else { return }
        let (lo, hi) = room(around: (region.start + region.end) / 2, excluding: id)
        var regions = take.speedRegions
        guard let i = regions.firstIndex(where: { $0.id == id }) else { return }
        body(&regions[i], lo, hi)
        // A resize that would cut the whole clip stops where it is.
        guard TimeMap(trim: take.trim, regions: regions).duration >= Self.clipMinimum else { return }
        change { $0.speedRegions = regions }
    }
}
