import CoreGraphics
import Foundation
import Observation

/// Every edit the editor makes to a take (spec 6.2 to 6.4), each one undo step. Zooms stay sorted,
/// inside the trim, at least `moveIn + moveOut + 0.2` s long, and never overlap after an edit.
@Observable
public final class EditorModel {
    public enum Edge: Sendable { case start, end }
    /// What the stage, the timeline and the inspector have selected.
    public enum Selection: Hashable, Sendable { case zoom(Zoom.ID), caption(Caption.ID), camera, speed(SpeedRegion.ID) }

    public static let minGap = 0.2
    public static let depthRange = 1.0...3.0
    public static let moveRange = 0.2...1.5
    public static let addedHold = 1.5

    public private(set) var take: Take
    public var selection: Selection?
    public var playhead: Double = 0
    /// Redrawn when the look's pointer settings change, so preview and export follow at once.
    public private(set) var pointer: PointerPath?
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

    /// The selected zoom, for the callers that only know zooms.
    public var selectedZoom: Zoom.ID? {
        get { if case .zoom(let id) = selection { id } else { nil } }
        set { selection = newValue.map(Selection.zoom) }
    }

    public var zoomCountText: String {
        guard let id = selectedZoom, let i = take.zooms.firstIndex(where: { $0.id == id }) else { return "" }
        return "Zoom \(i + 1) of \(take.zooms.count)"
    }

    // MARK: Selection

    public func select(_ id: Zoom.ID?) { selectedZoom = id }
    public func selectCaption(_ id: Caption.ID) { selection = .caption(id) }
    public func selectCamera() { selection = take.camera == nil ? nil : .camera }

    public func selectNext() {
        guard !take.zooms.isEmpty else { return }
        let i = take.zooms.firstIndex { $0.id == selectedZoom } ?? -1
        selectedZoom = take.zooms[(i + 1) % take.zooms.count].id
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

    /// Moves never outgrow the zoom: each is capped so `moveIn + moveOut + 0.2` still fits.
    public func setMove(_ id: Zoom.ID, moveIn: Double?, moveOut: Double?) {
        edit(id) { z, _, _ in
            let length = z.length
            func room(_ other: Double) -> Double {
                max(min(Self.moveRange.upperBound, length - Self.minGap - other), Self.moveRange.lowerBound)
            }
            if let moveIn { z.moveIn = min(Self.clamp(moveIn, Self.moveRange), room(z.moveOut)) }
            if let moveOut { z.moveOut = min(Self.clamp(moveOut, Self.moveRange), room(z.moveIn)) }
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
        selectedZoom = zoom.id
    }

    public func remove(_ id: Zoom.ID) {
        guard zoom(id) != nil else { return }
        change { $0.zooms.removeAll { $0.id == id } }
        if selectedZoom == id { selection = nil }
    }

    /// Clamps zooms into the new trim; a zoom left shorter than its minimum is removed.
    public func setTrim(_ r: ClosedRange<Double>) {
        let range = max(r.lowerBound, 0)...min(r.upperBound, take.duration)
        // The trim stops before cuts and speed-ups leave less than half a second of clip.
        guard TimeMap(trim: range, regions: take.speedRegions).duration >= Self.clipMinimum else { return }
        // During a drag, start from the zooms before it, so dragging back brings them back.
        let zooms = gestureStart?.zooms ?? take.zooms
        change { take in
            take.trim = range
            take.zooms = zooms.compactMap { z in
                var z = z
                z.start = max(z.start, range.lowerBound)
                z.end = min(z.end, range.upperBound)
                return z.length >= Self.minimumLength(z) - 1e-9 ? z : nil
            }
        }
        if let s = selectedZoom, zoom(s) == nil { selection = nil }
    }

    public func setLook(_ l: Look) { change { $0.look = l } }

    // MARK: Studio: shape, backdrop and camera

    /// The stage's shape. Zooms stay as they are (spec 5.3).
    public func setShape(_ s: ShapePreset) { change { $0.shape = s } }

    public func setBackdrop(_ b: Look.Background) { change { $0.look.background = b } }

    public func setCamera(_ body: (inout CameraTrack) -> Void) {
        guard take.camera != nil else { return }
        change { take in
            guard var camera = take.camera else { return }
            body(&camera)
            camera.size = Self.clamp(camera.size, CameraTrack.sizeRange)
            take.camera = camera
        }
    }

    /// Hides the camera from `t0` to `t1`, joined with any hidden stretch it touches.
    public func hideCamera(from t0: Double, to t1: Double) {
        let lo = max(min(t0, t1), 0), hi = min(max(t0, t1), take.duration)
        guard hi - lo >= Self.minGap else { return }
        setCamera { camera in
            var merged = lo...hi
            var rest: [ClosedRange<Double>] = []
            for r in camera.hidden {
                if r.lowerBound <= merged.upperBound && merged.lowerBound <= r.upperBound {
                    merged = min(r.lowerBound, merged.lowerBound)...max(r.upperBound, merged.upperBound)
                } else {
                    rest.append(r)
                }
            }
            camera.hidden = (rest + [merged]).sorted { $0.lowerBound < $1.lowerBound }
        }
    }

    public func showCamera(range index: Int) {
        setCamera { if $0.hidden.indices.contains(index) { $0.hidden.remove(at: index) } }
    }

    /// Drags one end of a hidden stretch; it stops at its neighbors and stays at least 0.2 s long.
    public func resizeCameraGap(index: Int, edge: Edge, to t: Double) {
        setCamera { camera in
            guard camera.hidden.indices.contains(index) else { return }
            let r = camera.hidden[index]
            let lo = index > 0 ? camera.hidden[index - 1].upperBound : 0
            let hi = index + 1 < camera.hidden.count ? camera.hidden[index + 1].lowerBound : take.duration
            switch edge {
            case .start: camera.hidden[index] = min(max(t, lo), r.upperBound - Self.minGap)...r.upperBound
            case .end: camera.hidden[index] = r.lowerBound...max(min(t, hi), r.lowerBound + Self.minGap)
            }
        }
    }

    // MARK: Studio: captions

    public static let captionMinimum = 0.4
    public static let addedCaption = 2.0

    public func caption(_ id: Caption.ID) -> Caption? { take.captions?.items.first { $0.id == id } }

    /// A fresh transcription. Clears `edited`, so Transcribe again stops asking.
    public func setCaptions(_ track: CaptionTrack) {
        var track = track
        track.items.sort { $0.start < $1.start }
        track.edited = false
        change { $0.captions = track }
        if case .caption(let id) = selection, caption(id) == nil { selection = nil }
    }

    /// The caption track's own settings (position, size, the .srt switch); not a caption edit.
    public func setCaptionStyle(_ body: (inout CaptionTrack) -> Void) {
        change { take in
            guard var track = take.captions else { return }
            body(&track)
            track.size = Self.clamp(track.size, CaptionTrack.sizeRange)
            take.captions = track
        }
    }

    /// A typed caption at `t`, 2 s or up to the next one, empty and selected. Nothing when less than
    /// 0.4 s is free there.
    public func addCaption(at t: Double) {
        let items = take.captions?.items ?? []
        guard t >= take.trim.lowerBound, !items.contains(where: { $0.start <= t && t < $0.end }) else { return }
        let next = items.first { $0.start > t }?.start ?? take.trim.upperBound
        let end = min(t + Self.addedCaption, next, take.trim.upperBound)
        guard end - t >= Self.captionMinimum else { return }
        let added = Caption(start: t, end: end, text: "")
        editCaptions { track in
            track.items.append(added)
            track.items.sort { $0.start < $1.start }
        }
        selection = .caption(added.id)
    }

    public func editCaption(_ id: Caption.ID, text: String) {
        editCaption(id) { c, _, _ in c.text = text }
    }

    public func removeCaption(_ id: Caption.ID) {
        guard caption(id) != nil else { return }
        editCaptions { $0.items.removeAll { $0.id == id } }
        if selection == .caption(id) { selection = nil }
    }

    /// Return in the caption field: the text splits at the cursor and the time in proportion to the
    /// characters on each side.
    public func splitCaption(_ id: Caption.ID, at characterIndex: Int) {
        guard let c = caption(id), characterIndex > 0, characterIndex < c.text.count else { return }
        let cut = c.text.index(c.text.startIndex, offsetBy: characterIndex)
        let left = c.text[..<cut].trimmingCharacters(in: .whitespaces), right = c.text[cut...].trimmingCharacters(in: .whitespaces)
        guard !left.isEmpty, !right.isEmpty else { return }
        let at = c.start + (c.end - c.start) * Double(characterIndex) / Double(c.text.count)
        let second = Caption(start: at, end: c.end, text: right)
        editCaptions { track in
            guard let i = track.items.firstIndex(where: { $0.id == id }) else { return }
            track.items[i].text = left
            track.items[i].end = at
            track.items.insert(second, at: i + 1)
        }
        selection = .caption(second.id)
    }

    /// Delete at the start of the caption field: joins it onto the one before.
    public func joinCaption(_ id: Caption.ID) {
        guard let items = take.captions?.items, let i = items.firstIndex(where: { $0.id == id }), i > 0 else { return }
        let before = items[i - 1].id
        editCaptions { track in
            let c = track.items.remove(at: i)
            track.items[i - 1].text = [track.items[i - 1].text, c.text].filter { !$0.isEmpty }.joined(separator: " ")
            track.items[i - 1].end = c.end
        }
        selection = .caption(before)
    }

    public func moveCaption(_ id: Caption.ID, by dt: Double) {
        editCaption(id) { c, lo, hi in
            let shift = min(max(dt, lo - c.start), hi - c.end)
            c.start += shift
            c.end += shift
        }
    }

    public func resizeCaption(_ id: Caption.ID, edge: Edge, to t: Double) {
        editCaption(id) { c, lo, hi in
            switch edge {
            case .start: c.start = min(max(t, lo), c.end - Self.captionMinimum)
            case .end: c.end = max(min(t, hi), c.start + Self.captionMinimum)
            }
        }
    }

    private func editCaptions(_ body: (inout CaptionTrack) -> Void) {
        change { take in
            var track = take.captions ?? CaptionTrack(source: .typed, locale: Locale.current.identifier)
            body(&track)
            track.edited = true
            take.captions = track
        }
    }

    /// Runs `body` on one caption with the bounds its neighbors and the trim leave it.
    private func editCaption(_ id: Caption.ID, _ body: (inout Caption, Double, Double) -> Void) {
        guard let items = take.captions?.items, let i = items.firstIndex(where: { $0.id == id }) else { return }
        let lo = max(i > 0 ? items[i - 1].end : 0, take.trim.lowerBound)
        let hi = min(i + 1 < items.count ? items[i + 1].start : take.duration, take.trim.upperBound)
        editCaptions { body(&$0.items[i], lo, hi) }
    }

    /// The toolbar's name field. Blank names are ignored.
    public func renameTake(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        change { $0.name = trimmed }
    }

    /// Zoom names read from the screen after the take opened. Not an edit, so it is not undoable.
    public func apply(_ updates: [ZoomNameUpdate]) {
        var updated = take
        if updated.apply(updates) { take = updated }
    }

    /// Notes a finished export on the take. Not an edit, so it is not undoable.
    public func recordExport(_ record: ExportRecord) { take.exports.append(record) }

    public func beginGesture() { gestureStart = take }

    public func endGesture() {
        if let start = gestureStart, start != take { history.record(start) }
        gestureStart = nil
    }

    /// Exports are not edits, so undo and redo keep the current list.
    public func undo() {
        if var previous = history.undo(take) {
            previous.exports = take.exports
            set(previous)
        }
    }

    public func redo() {
        if var next = history.redo(take) {
            next.exports = take.exports
            set(next)
        }
    }

    private func set(_ next: Take) {
        let old = take.look
        take = next
        // Undo can take away what is selected.
        let selected: Bool = switch selection {
        case .zoom(let id): next.zooms.contains { $0.id == id }
        case .caption(let id): next.captions?.items.contains { $0.id == id } ?? false
        case .speed(let id): next.speedRegions.contains { $0.id == id }
        case .camera: next.camera != nil
        case nil: true
        }
        if !selected { selection = nil }
        if let pointer, old.smoothPointer != next.look.smoothPointer || old.hideWhenStill != next.look.hideWhenStill {
            self.pointer = pointer.with(look: next.look)
        }
    }

    // MARK: Helpers

    static func minimumLength(_ z: Zoom) -> Double { z.moveIn + z.moveOut + minGap }

    private static func clamp(_ v: Double, _ r: ClosedRange<Double>) -> Double { min(max(v, r.lowerBound), r.upperBound) }

    private func clampAim(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), take.size.width), y: min(max(p.y, 0), take.size.height))
    }

    func change(_ body: (inout Take) -> Void) {
        var next = take
        body(&next)
        guard next != take else { return }
        if gestureStart == nil { history.record(take) }
        set(next)
    }

    /// Runs `body` on one zoom with the bounds its neighbors and the trim leave it.
    private func edit(_ id: Zoom.ID, _ body: @escaping (inout Zoom, Double, Double) -> Void) {
        guard let i = take.zooms.firstIndex(where: { $0.id == id }) else { return }
        let lo = i > 0 ? take.zooms[i - 1].end : take.trim.lowerBound
        let hi = i + 1 < take.zooms.count ? take.zooms[i + 1].start : take.trim.upperBound
        change { body(&$0.zooms[i], max(lo, $0.trim.lowerBound), min(hi, $0.trim.upperBound)) }
    }
}
