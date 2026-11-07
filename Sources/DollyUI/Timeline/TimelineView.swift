import AppKit
import DollyCore
import SwiftUI

/// The timeline (spec 6.3, studio spec item 6): play and time, the length line, then the ruler and
/// five lanes. Zooms are pink tape strips; the strip and the stage's corners are one selection. The
/// camera lane shows where the webcam shows; captions are chips. Drags follow the pointer 1:1 and
/// each is one undo step; a strip or caption added or removed bridges with 160 ms (spec 10.6).
public struct TimelineView: View {
    @Bindable var editor: EditorModel
    let clickTimes: [Double]
    let filmstrip: Filmstrip?
    let playback: (any PlaybackControlling)?
    let isPlaying: Bool
    @State private var drag: DragState?
    @State private var ghost: ClosedRange<Double>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct DragState {
        var hit: TimelineHit
        var zoom: Zoom?
        var caption: Caption?
        var speed: SpeedRegion?
        var moved = false
    }

    public init(editor: EditorModel, clickTimes: [Double], filmstrip: Filmstrip?, playback: (any PlaybackControlling)?, isPlaying: Bool) {
        self.editor = editor
        self.clickTimes = clickTimes
        self.filmstrip = filmstrip
        self.playback = playback
        self.isPlaying = isPlaying
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(alignment: .top, spacing: 0) {
                laneNames.frame(width: TimelineLayout.labelColumn, height: TimelineLayout.height, alignment: .topLeading)
                GeometryReader { geo in
                    lanes(TimelineLayout(width: geo.size.width, duration: editor.take.duration))
                }
                .frame(height: TimelineLayout.height)
            }
            Group {
                if let id = editor.selectedSpeed, let region = editor.speedRegion(id) {
                    SpeedBar(editor: editor, region: region)
                } else {
                    Text(TimelineHint.text(clicks: clickTimes.count, zooms: editor.take.zooms.count))
                        .font(Theme.Font.meta)
                        .monospacedDigit()
                        .foregroundStyle(Theme.muted.color)
                }
            }
            .frame(height: SpeedBar.height, alignment: .leading)
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { key in
            guard let action = TimelineInput.action(key: key.key, shift: key.modifiers.contains(.shift),
                                                    command: key.modifiers.contains(.command)) else { return .ignored }
            TimelineInput.apply(action, to: editor, playback: playback)
            return .handled
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { playback?.togglePlay() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink.color)
            }
            .buttonStyle(IconButtonStyle())
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            PlayClock(editor: editor)
            Spacer()
            Text(PlatformLimits.lengthLine(editor.take.outputDuration))
                .font(Theme.Font.body)
                .monospacedDigit()
                .foregroundStyle(Theme.muted.color)
        }
        .frame(height: 32)
    }

    private var laneNames: some View {
        ZStack(alignment: .topLeading) {
            ForEach([("Video", TimelineLayout.videoLane), ("Speed", TimelineLayout.speedLane), ("Zoom", TimelineLayout.zoomLane), ("Camera", TimelineLayout.cameraLane),
                     ("Captions", TimelineLayout.captionLane), ("Clicks", TimelineLayout.clickLane)], id: \.0) { name, lane in
                Text(name).font(Theme.Font.meta).foregroundStyle(Theme.muted.color)
                    .offset(y: lane.minY + (name == "Zoom" ? 8 : lane.height / 2 - 8))
            }
        }
    }

    private func lanes(_ layout: TimelineLayout) -> some View {
        ZStack(alignment: .topLeading) {
            let frames = filmstrip?.frames ?? []
            Canvas { context, size in draw(&context, size: size, layout: layout, frames: frames) }
                .accessibilityHidden(true)
            gestureLayer(layout)
            ForEach(Array(editor.take.zooms.enumerated()), id: \.element.id) { index, zoom in
                strip(zoom, index: index, layout: layout)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            }
            let speeds = editor.take.speedRegions
            ForEach(Array(speeds.enumerated()), id: \.element.id) { index, region in
                speedView(region, index: index, count: speeds.count, layout: layout)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            }
            let captions = editor.take.captions?.items ?? []
            ForEach(Array(captions.enumerated()), id: \.element.id) { index, caption in
                chip(caption, index: index, count: captions.count, layout: layout)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            }
            if let ghost, let hit = drag?.hit, case .emptySpeedLane = hit {
                let lane = TimelineLayout.speedLane
                RoundedRectangle(cornerRadius: 4).fill(Theme.control.color.opacity(0.7))
                    .frame(width: max(layout.x(for: ghost.upperBound - ghost.lowerBound), 1), height: lane.height - 2 * TimelineLayout.laneInset)
                    .offset(x: layout.x(for: ghost.lowerBound), y: lane.minY + TimelineLayout.laneInset)
                    .allowsHitTesting(false)
            } else if let ghost, let hit = drag?.hit {
                let camera = { if case .cameraBar = hit { true } else { false } }()
                let lane = camera ? TimelineLayout.cameraLane : TimelineLayout.zoomLane
                Rectangle().fill(camera ? Theme.scrim.color : Theme.tape.color.opacity(0.5))
                    .frame(width: max(layout.x(for: ghost.upperBound - ghost.lowerBound), 1),
                           height: camera ? lane.height - 2 * TimelineLayout.laneInset : TimelineLayout.stripHeight)
                    .offset(x: layout.x(for: ghost.lowerBound), y: lane.minY + (camera ? TimelineLayout.laneInset : TimelineLayout.stripTop))
                    .allowsHitTesting(false)
            }
            PlayheadMark(editor: editor, layout: layout)
        }
        .coordinateSpace(.named("lanes"))
        .animation(.easeOut(duration: Theme.Motion.stripBridge), value: editor.take.zooms.map(\.id))
        .animation(.easeOut(duration: Theme.Motion.stripBridge), value: editor.take.captions?.items.map(\.id))
        .animation(.easeOut(duration: Theme.Motion.stripBridge), value: editor.take.speedRegions.map(\.id))
        .onContinuousHover(coordinateSpace: .named("lanes")) { phase in
            guard case .active(let p) = phase else { NSCursor.arrow.set(); return }
            switch layout.hit(p, zooms: editor.take.zooms, trim: editor.take.trim, camera: editor.take.camera,
                              captions: editor.take.captions?.items ?? [], speeds: editor.take.speedRegions) {
            case .strip(_, .startEdge), .strip(_, .endEdge), .trim, .cameraGap(_, .startEdge), .cameraGap(_, .endEdge),
                 .caption(_, .startEdge), .caption(_, .endEdge), .speed(_, .startEdge), .speed(_, .endEdge): NSCursor.resizeLeftRight.set()
            case .strip(_, .body), .caption(_, .body), .speed(_, .body): NSCursor.openHand.set()
            default: NSCursor.arrow.set()
            }
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, layout: TimelineLayout, frames: [Image]) {
        let ink = Theme.ink.color, muted = Theme.muted.color, control = Theme.control.color, raised = Theme.raised.color
        for tick in layout.rulerTicks {
            context.fill(Path(CGRect(x: tick.x, y: 0, width: 1, height: 14)), with: .color(control))
            context.draw(Text(tick.label).font(Theme.Font.tick).foregroundStyle(muted).monospacedDigit(),
                         at: CGPoint(x: tick.x + 4, y: 0), anchor: .topLeading)
        }
        let video = TimelineLayout.videoLane.insetBy(dx: 0, dy: 0).offsetBy(dx: 0, dy: 0)
        let videoRect = CGRect(x: 0, y: video.minY, width: size.width, height: video.height)
        let rounded = Path(roundedRect: videoRect, cornerRadius: Theme.Size.controlRadius)
        context.fill(rounded, with: .color(raised))
        if !frames.isEmpty {
            context.drawLayer { layer in
                layer.clip(to: rounded)
                var x: CGFloat = 0
                while x < size.width {
                    let t = layout.t(for: x + videoRect.height / 2)
                    let frame = frames[Filmstrip.index(at: t, duration: editor.take.duration, count: frames.count)]
                    layer.draw(frame, in: CGRect(x: x, y: videoRect.minY, width: videoRect.height, height: videoRect.height))
                    x += videoRect.height
                }
            }
        }
        let trim = editor.take.trim
        let start = layout.x(for: trim.lowerBound), end = layout.x(for: trim.upperBound)
        context.fill(Path(CGRect(x: 0, y: videoRect.minY, width: start, height: videoRect.height)), with: .color(.black.opacity(0.45)))
        context.fill(Path(CGRect(x: end, y: videoRect.minY, width: size.width - end, height: videoRect.height)), with: .color(.black.opacity(0.45)))
        context.fill(Path(roundedRect: CGRect(x: start, y: videoRect.minY, width: 10, height: videoRect.height), cornerRadius: 3), with: .color(ink))
        context.fill(Path(roundedRect: CGRect(x: end - 10, y: videoRect.minY, width: 10, height: videoRect.height), cornerRadius: 3), with: .color(ink))
        // Cut stretches are shaded like the trimmed ends: they are not in the clip.
        for region in editor.take.speedRegions where region.speed == .cut {
            let x0 = layout.x(for: region.start), x1 = layout.x(for: region.end)
            context.fill(Path(CGRect(x: x0, y: videoRect.minY, width: x1 - x0, height: videoRect.height)), with: .color(.black.opacity(0.45)))
        }
        let speedLane = CGRect(x: 0, y: TimelineLayout.speedLane.minY, width: size.width, height: TimelineLayout.speedLane.height)
        context.fill(Path(roundedRect: speedLane, cornerRadius: Theme.Size.controlRadius), with: .color(raised))
        let zoomLane = CGRect(x: 0, y: TimelineLayout.zoomLane.minY, width: size.width, height: TimelineLayout.zoomLane.height)
        context.fill(Path(roundedRect: zoomLane, cornerRadius: Theme.Size.controlRadius), with: .color(raised))
        if let camera = editor.take.camera {
            let selected = editor.selection == .camera
            for bar in layout.cameraBars(camera) {
                let shape = Path(roundedRect: bar, cornerRadius: 4)
                context.fill(shape, with: .color(control))
                if selected { context.stroke(shape, with: .color(ink), lineWidth: 2) }
                if bar.width > 64 {
                    context.draw(Text("Camera").font(Theme.Font.meta).foregroundStyle(ink), at: CGPoint(x: bar.minX + 8, y: bar.midY),
                                 anchor: .leading)
                }
            }
        }
        let captionLane = CGRect(x: 0, y: TimelineLayout.captionLane.minY, width: size.width, height: TimelineLayout.captionLane.height)
        context.fill(Path(roundedRect: captionLane, cornerRadius: Theme.Size.controlRadius), with: .color(raised))
        for t in clickTimes {
            context.fill(Path(ellipseIn: CGRect(x: layout.x(for: t) - 5, y: TimelineLayout.clickLane.minY + 5, width: 10, height: 10)), with: .color(ink))
        }
    }

    private func strip(_ zoom: Zoom, index: Int, layout: TimelineLayout) -> some View {
        let geometry = layout.strip(for: zoom)
        let selected = editor.selectedZoom == zoom.id
        let next = editor.take.zooms.first { $0.start > zoom.start }.map { layout.x(for: $0.start) } ?? layout.width
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Theme.tape.color)
                .frame(width: geometry.frame.width, height: geometry.frame.height)
            Rectangle().fill(Theme.onTape.color.opacity(0.16))
                .frame(width: geometry.inBand.width, height: geometry.frame.height)
            Rectangle().fill(Theme.onTape.color.opacity(0.16))
                .frame(width: geometry.outBand.width, height: geometry.frame.height)
                .offset(x: geometry.frame.width - geometry.outBand.width)
            Text(String(format: "%.1f×", zoom.depth))
                .font(Theme.Font.display(12))
                .foregroundStyle(Theme.onTape.color)
                .monospacedDigit()
                .padding(.leading, 6)
                .frame(height: geometry.frame.height)
            if selected {
                Rectangle().strokeBorder(Theme.ink.color, lineWidth: 2)
                    .frame(width: geometry.frame.width + 8, height: geometry.frame.height + 8)
                    .offset(x: -4, y: -4)
            }
            Text(zoom.name)
                .font(Theme.Font.tick)
                .foregroundStyle(Theme.muted.color)
                .lineLimit(1)
                .frame(width: max(next - geometry.frame.minX - 6, 20), alignment: .leading)
                .offset(y: geometry.frame.height + 6)
                .allowsHitTesting(false)
        }
        .frame(width: geometry.frame.width, height: geometry.frame.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .offset(x: geometry.frame.minX, y: geometry.frame.minY)
        .gesture(stripGesture(zoom, layout: layout))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TimelineAccessibility.label(zoom, index: index, count: editor.take.zooms.count))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction { editor.select(zoom.id) }
        .accessibilityAction(named: "Move earlier") { editor.move(zoom.id, by: -0.1) }
        .accessibilityAction(named: "Move later") { editor.move(zoom.id, by: 0.1) }
        .accessibilityAction(named: "Deeper") { editor.setDepth(zoom.id, zoom.depth + 0.1) }
        .accessibilityAction(named: "Shallower") { editor.setDepth(zoom.id, zoom.depth - 0.1) }
        .accessibilityAction(named: "Remove") { editor.remove(zoom.id) }
    }

    /// One caption on its lane: a sheet-colored chip with its words, ink-ringed when selected.
    private func chip(_ caption: Caption, index: Int, count: Int, layout: TimelineLayout) -> some View {
        let frame = layout.chip(for: caption)
        let selected = editor.selection == .caption(caption.id)
        let shape = RoundedRectangle(cornerRadius: 4)
        return Text(caption.text.isEmpty ? " " : caption.text)
            .font(Theme.Font.meta)
            .foregroundStyle(Theme.ink.color)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .frame(width: frame.width, height: frame.height, alignment: .leading)
            .background(shape.fill(Theme.sheet.color))
            .overlay(shape.strokeBorder(selected ? Theme.ink.color : Theme.control.color, lineWidth: selected ? 2 : 1))
            .clipShape(shape)
            .contentShape(Rectangle())
            .offset(x: frame.minX, y: frame.minY)
            .gesture(chipGesture(caption, layout: layout))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TimelineAccessibility.label(caption, index: index, count: count))
            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction { editor.selectCaption(caption.id) }
            .accessibilityAction(named: "Move earlier") { editor.moveCaption(caption.id, by: -0.1) }
            .accessibilityAction(named: "Move later") { editor.moveCaption(caption.id, by: 0.1) }
            .accessibilityAction(named: "Remove") { editor.removeCaption(caption.id) }
    }

    /// One cut or speed-up on the Speed lane: a cut in the control tone, a speed-up in ink.
    private func speedView(_ region: SpeedRegion, index: Int, count: Int, layout: TimelineLayout) -> some View {
        let frame = layout.speedRect(for: region)
        let selected = editor.selectedSpeed == region.id
        let cut = region.speed == .cut
        let shape = RoundedRectangle(cornerRadius: 4)
        return Text(region.speed.label)
            .font(Theme.Font.meta.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(cut ? Theme.ink.color : Theme.onPrimary.color)
            .lineLimit(1)
            .opacity(frame.width >= 32 ? 1 : 0)
            .padding(.horizontal, 6)
            .frame(width: frame.width, height: frame.height, alignment: .leading)
            .background(shape.fill(cut ? Theme.control.color : Theme.primary.color))
            .overlay {
                if selected { RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.ink.color, lineWidth: 2).padding(-3) }
            }
            .contentShape(Rectangle())
            .offset(x: frame.minX, y: frame.minY)
            .gesture(speedGesture(region, layout: layout))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(TimelineAccessibility.label(region, index: index, count: count))
            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction { editor.selection = .speed(region.id) }
            .accessibilityAction(named: "Move earlier") { editor.moveSpeed(region.id, by: -0.1) }
            .accessibilityAction(named: "Move later") { editor.moveSpeed(region.id, by: 0.1) }
            .accessibilityAction(named: "Remove") { editor.removeSpeed(region.id) }
    }

    private func speedGesture(_ region: SpeedRegion, layout: TimelineLayout) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("lanes"))
            .onChanged { value in
                if drag == nil {
                    drag = DragState(hit: layout.hit(value.startLocation, zooms: [], speeds: [region]), speed: region)
                    editor.selection = .speed(region.id)
                    editor.beginGesture()
                }
                guard var state = drag, let start = state.speed else { return }
                guard abs(value.translation.width) >= 1 || state.moved else { return }
                state.moved = true
                drag = state
                switch state.hit {
                case .speed(_, .startEdge): editor.resizeSpeed(region.id, edge: .start, to: layout.t(for: value.location.x))
                case .speed(_, .endEdge): editor.resizeSpeed(region.id, edge: .end, to: layout.t(for: value.location.x))
                default:
                    let target = start.start + layout.t(for: abs(value.translation.width)) * (value.translation.width < 0 ? -1 : 1)
                    editor.moveSpeed(region.id, by: target - (editor.speedRegion(region.id)?.start ?? start.start))
                }
            }
            .onEnded { _ in
                editor.endGesture()
                drag = nil
            }
    }

    private func chipGesture(_ caption: Caption, layout: TimelineLayout) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("lanes"))
            .onChanged { value in
                if drag == nil {
                    drag = DragState(hit: layout.hit(value.startLocation, zooms: [], captions: [caption]), caption: caption)
                    editor.selectCaption(caption.id)
                    editor.beginGesture()
                }
                guard var state = drag, let start = state.caption else { return }
                guard abs(value.translation.width) >= 1 || state.moved else { return }
                state.moved = true
                drag = state
                switch state.hit {
                case .caption(_, .startEdge): editor.resizeCaption(caption.id, edge: .start, to: layout.t(for: value.location.x))
                case .caption(_, .endEdge): editor.resizeCaption(caption.id, edge: .end, to: layout.t(for: value.location.x))
                default:
                    let target = start.start + layout.t(for: abs(value.translation.width)) * (value.translation.width < 0 ? -1 : 1)
                    editor.moveCaption(caption.id, by: target - (editor.caption(caption.id)?.start ?? start.start))
                }
            }
            .onEnded { _ in
                editor.endGesture()
                drag = nil
            }
    }

    private func stripGesture(_ zoom: Zoom, layout: TimelineLayout) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("lanes"))
            .onChanged { value in
                if drag == nil {
                    drag = DragState(hit: layout.hit(value.startLocation, zooms: editor.take.zooms), zoom: zoom)
                    editor.select(zoom.id)
                    editor.beginGesture()
                }
                guard var state = drag, let start = state.zoom else { return }
                guard abs(value.translation.width) >= 1 || state.moved else { return }
                state.moved = true
                drag = state
                switch state.hit {
                case .strip(_, .startEdge): editor.resize(zoom.id, edge: .start, to: layout.t(for: value.location.x))
                case .strip(_, .endEdge): editor.resize(zoom.id, edge: .end, to: layout.t(for: value.location.x))
                default:
                    let target = start.start + layout.t(for: abs(value.translation.width)) * (value.translation.width < 0 ? -1 : 1)
                    editor.move(zoom.id, by: target - (editor.zoom(zoom.id)?.start ?? start.start))
                }
            }
            .onEnded { _ in
                editor.endGesture()
                drag = nil
            }
    }

    private func gestureLayer(_ layout: TimelineLayout) -> some View {
        Color.white.opacity(0.001)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("lanes"))
                .onChanged { value in
                    if drag == nil {
                        drag = DragState(hit: layout.hit(value.startLocation, zooms: editor.take.zooms, trim: editor.take.trim,
                                                         camera: editor.take.camera, captions: editor.take.captions?.items ?? [],
                                                         speeds: editor.take.speedRegions))
                        switch drag?.hit {
                        case .trim, .cameraGap(_, .startEdge), .cameraGap(_, .endEdge): editor.beginGesture()
                        default: break
                        }
                    }
                    let t = layout.t(for: value.location.x)
                    if abs(value.translation.width) > 4 { drag?.moved = true }
                    switch drag?.hit {
                    case .ruler: editor.playhead = t
                    case .emptyZoomLane(let t0), .cameraBar(let t0), .emptySpeedLane(let t0):
                        if abs(value.translation.width) > 4 { ghost = min(t0, t)...max(t0, t) }
                    case .cameraGap(let i, .startEdge): editor.resizeCameraGap(index: i, edge: .start, to: t)
                    case .cameraGap(let i, .endEdge): editor.resizeCameraGap(index: i, edge: .end, to: t)
                    case .trim(.start): editor.setTrim(min(t, editor.take.trim.upperBound - 1)...editor.take.trim.upperBound)
                    case .trim(.end): editor.setTrim(editor.take.trim.lowerBound...max(t, editor.take.trim.lowerBound + 1))
                    default: break
                    }
                }
                .onEnded { value in
                    switch drag?.hit {
                    case .emptyZoomLane(let t0):
                        if let ghost { editor.addZoom(from: ghost.lowerBound, to: ghost.upperBound) } else {
                            editor.select(nil)
                            editor.playhead = t0
                        }
                    case .emptySpeedLane(let t0):
                        if let ghost { editor.addSpeed(from: t0 == ghost.lowerBound ? ghost.lowerBound : ghost.upperBound,
                                                       to: t0 == ghost.lowerBound ? ghost.upperBound : ghost.lowerBound, speed: .cut) } else {
                            editor.select(nil)
                            editor.playhead = t0
                        }
                    case .trim, .cameraGap(_, .startEdge), .cameraGap(_, .endEdge): editor.endGesture()
                    case .some(let hit):
                        let t0: Double = switch hit {
                        case .cameraBar(let t), .emptyCaptionLane(let t): t
                        default: layout.t(for: value.startLocation.x)
                        }
                        TimelineInput.finishDrag(hit, from: t0, to: layout.t(for: value.location.x), moved: drag?.moved ?? false,
                                                 editor: editor)
                    case nil: break
                    }
                    ghost = nil
                    drag = nil
                })
    }
}

/// The clock and the playhead line are their own views so that playback, which moves the playhead
/// 30 times a second, redraws only them and not the lanes' Canvas.
private struct PlayClock: View {
    let editor: EditorModel

    var body: some View {
        let map = editor.take.timeMap
        HStack(spacing: 0) {
            Text(TimeText.clock(map.output(at: editor.playhead))).foregroundStyle(Theme.ink.color)
            Text(" / \(TimeText.clock(map.duration))").foregroundStyle(Theme.muted.color)
        }
        .font(.system(size: 15, weight: .medium))
        .monospacedDigit()
    }
}

private struct PlayheadMark: View {
    let editor: EditorModel
    let layout: TimelineLayout

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(Theme.ink.color).frame(width: 2, height: TimelineLayout.height + 4)
            RoundedRectangle(cornerRadius: 2).fill(Theme.ink.color).frame(width: 12, height: 8)
        }
        .offset(x: layout.x(for: editor.playhead) - 6, y: -4)
        .allowsHitTesting(false)
    }
}

/// Under the timeline while a cut or speed-up is selected: what it does, its speed, Remove.
private struct SpeedBar: View {
    static let height: CGFloat = 30
    let editor: EditorModel
    let region: SpeedRegion

    var body: some View {
        HStack(spacing: 12) {
            StudioSegmented(SpeedRegion.Speed.choices, selected: region.speed, label: \.label) { editor.setSpeed(region.id, $0) }
                .fixedSize()
            Text(SpeedBar.summary(region))
                .font(Theme.Font.meta)
                .monospacedDigit()
                .foregroundStyle(Theme.muted.color)
            Spacer(minLength: 0)
            Button("Remove") { editor.removeSpeed(region.id) }.buttonStyle(DollyButtonStyle())
        }
    }

    /// "Removes 2.0 s" or "Plays 4.0 s in 1.0 s".
    nonisolated static func summary(_ region: SpeedRegion) -> String {
        let length = String(format: "%.1f s", region.length)
        return switch region.speed {
        case .cut: "Removes \(length)"
        case .fast(let rate): "Plays \(length) in " + String(format: "%.1f s", region.length / rate)
        }
    }
}
