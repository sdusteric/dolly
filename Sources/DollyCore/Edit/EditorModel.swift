import CoreGraphics
import Foundation
import Observation

/// Every edit the editor makes to a take (spec 6.2 to 6.4), each one undo step. Zooms stay sorted,
/// inside the trim, at least `moveIn + moveOut + 0.2` s long, and never overlap after an edit.
@Observable
public final class EditorModel {
    public enum Edge: Sendable { case start, end }

    public static let minGap = 0.2
    public static let depthRange = 1.0...3.0
    public static let moveRange = 0.2...1.5
    public static let addedHold = 1.5

    public private(set) var take: Take
    public var selection: Zoom.ID?
    public var playhead: Double = 0
    public let pointer: PointerPath?
    @ObservationIgnored private var history = UndoStack()
    /// While a drag runs, edits apply live and become one undo step when it ends.
    @ObservationIgnored private var gestureStart: Take?

    public init(take: Take, pointer: PointerPath?) {
        self.take = take
        self.pointer = pointer
        self.take.zooms.sort { $0.start < $1.start }
    }

    public var canUndo: Bool { history.canUndo }
    public var canRedo: Bool { history.canRedo }

    public func zoom(_ id: Zoom.ID) -> Zoom? { take.zooms.first { $0.id == id } }

    public var zoomCountText: String {
        guard let id = selection, let i = take.zooms.firstIndex(where: { $0.id == id }) else { return "" }
        return "Zoom \(i + 1) of \(take.zooms.count)"
    }

    // MARK: Selection

    public func select(_ id: Zoom.ID?) { selection = id }

    public func selectNext() {
        guard !take.zooms.isEmpty else { return }
        let i = take.zooms.firstIndex { $0.id == selection } ?? -1
        selection = take.zooms[(i + 1) % take.zooms.count].id
    }

    // MARK: Edits

    public func move(_ id: Zoom.ID, by dt: Double) {
        edit(id) { z, lo, hi in
            let shift = min(max(dt, lo - z.start), hi - z.end)
            z.start += shift
            z.end += shift
        }
    }

    public func resize(_ id: Zoom.ID, edge: Edge, to t: Double) {
        edit(id) { z, lo, hi in
            let minimum = Self.minimumLength(z)
            switch edge {
            case .start: z.start = min(max(t, lo), z.end - minimum)
            case .end: z.end = max(min(t, hi), z.start + minimum)
            }
        }
    }

    public func setDepth(_ id: Zoom.ID, _ d: Double) {
        edit(id) { z, _, _ in z.depth = Self.clamp(d, Self.depthRange) }
    }

    public func aim(_ id: Zoom.ID, at p: CGPoint) {
        edit(id) { z, _, _ in z.aim = self.clampAim(p) }
    }

    public func nudgeAim(_ id: Zoom.ID, dx: Double, dy: Double) {
        edit(id) { z, _, _ in z.aim = self.clampAim(CGPoint(x: z.aim.x + dx, y: z.aim.y + dy)) }
    }

    public func setMode(_ id: Zoom.ID, _ m: Zoom.Mode) {
        edit(id) { z, _, _ in z.mode = m }
    }

    public func setMove(_ id: Zoom.ID, moveIn: Double?, moveOut: Double?) {
        edit(id) { z, _, _ in
            if let moveIn { z.moveIn = Self.clamp(moveIn, Self.moveRange) }
            if let moveOut { z.moveOut = Self.clamp(moveOut, Self.moveRange) }
        }
    }

    public func rename(_ id: Zoom.ID, _ name: String) {
        edit(id) { z, _, _ in z.name = name }
    }

    /// A manual zoom at `t`: 2.0x, aimed at the logged pointer, `moveIn + 1.5 + moveOut` long.
    /// Does nothing when another zoom leaves no room there.
    public func addZoom(at t: Double) {
        let rules = ZoomRules()
        addZoom(from: t, to: t + rules.moveIn + Self.addedHold + rules.moveOut)
    }

    public func addZoom(from t0: Double, to t1: Double) {
        let rules = ZoomRules()
        let start = max(min(t0, t1), take.trim.lowerBound)
        let end = min(max(t0, t1), take.trim.upperBound)
        let aim = pointer?.rawPosition(at: start) ?? CGPoint(x: take.size.width / 2, y: take.size.height / 2)
        let zoom = Zoom(start: start, end: end, aim: clampAim(aim), depth: 2.0, mode: .hold,
                        moveIn: rules.moveIn, moveOut: rules.moveOut, source: .manual, clickIDs: [],
                        name: "Added at \(TimeText.clock(start))")
        guard end - start >= Self.minimumLength(zoom),
              !take.zooms.contains(where: { $0.start < end && start < $0.end }) else { return }
        change {
            $0.zooms.append(zoom)
            $0.zooms.sort { $0.start < $1.start }
        }
        selection = zoom.id
    }

    public func remove(_ id: Zoom.ID) {
        guard zoom(id) != nil else { return }
        change { $0.zooms.removeAll { $0.id == id } }
        if selection == id { selection = nil }
    }

    /// Clamps zooms into the new trim; a zoom left shorter than its minimum is removed.
    public func setTrim(_ r: ClosedRange<Double>) {
        let range = max(r.lowerBound, 0)...min(r.upperBound, take.duration)
        change { take in
            take.trim = range
            take.zooms = take.zooms.compactMap { z in
                var z = z
                z.start = max(z.start, range.lowerBound)
                z.end = min(z.end, range.upperBound)
                return z.length >= Self.minimumLength(z) - 1e-9 ? z : nil
            }
        }
        if let s = selection, zoom(s) == nil { selection = nil }
    }

    public func setLook(_ l: Look) { change { $0.look = l } }

    public func beginGesture() { gestureStart = take }

    public func endGesture() {
        if let start = gestureStart, start != take { history.record(start) }
        gestureStart = nil
    }

    public func undo() {
        if let previous = history.undo(take) { take = previous }
    }

    public func redo() {
        if let next = history.redo(take) { take = next }
    }

    // MARK: Helpers

    static func minimumLength(_ z: Zoom) -> Double { z.moveIn + z.moveOut + minGap }

    private static func clamp(_ v: Double, _ r: ClosedRange<Double>) -> Double { min(max(v, r.lowerBound), r.upperBound) }

    private func clampAim(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), take.size.width), y: min(max(p.y, 0), take.size.height))
    }

    private func change(_ body: (inout Take) -> Void) {
        var next = take
        body(&next)
        guard next != take else { return }
        if gestureStart == nil { history.record(take) }
        take = next
    }

    /// Runs `body` on one zoom with the bounds its neighbors and the trim leave it.
    private func edit(_ id: Zoom.ID, _ body: @escaping (inout Zoom, Double, Double) -> Void) {
        guard let i = take.zooms.firstIndex(where: { $0.id == id }) else { return }
        let lo = i > 0 ? take.zooms[i - 1].end : take.trim.lowerBound
        let hi = i + 1 < take.zooms.count ? take.zooms[i + 1].start : take.trim.upperBound
        change { body(&$0.zooms[i], max(lo, $0.trim.lowerBound), min(hi, $0.trim.upperBound)) }
    }
}
