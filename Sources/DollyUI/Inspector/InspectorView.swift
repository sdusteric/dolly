import DollyCore
import SwiftUI

nonisolated public enum InspectorModel {
    /// "0:07.3 to 0:09.9, 2.6 s. From your click at 0:07.9." or "... Added by you."
    public static func subtitle(_ zoom: Zoom, clicks: [Click]) -> String {
        let span = "\(TimeText.clock(zoom.start)) to \(TimeText.clock(zoom.end)), \(TimeText.seconds(zoom.length))."
        if zoom.source == .manual { return span + " Added by you." }
        guard let id = zoom.clickIDs.first, let click = clicks.first(where: { $0.id == id }) else { return span }
        return span + " From your click at \(TimeText.clock(click.t))."
    }

    public static func depthText(_ d: Double) -> String { String(format: "%.1f×", d) }
    public static func secondsText(_ s: Double) -> String { TimeText.seconds(s) }
    public static func pointsText(_ p: Double) -> String { "\(Int(p.rounded())) pt" }

    public static func useForNewTakes(_ look: Look, store: SettingsStore) throws {
        var settings = try store.load()
        settings.defaultLook = look
        try store.save(settings)
    }
}

/// The inspector (spec 6.4): the selected zoom, then the take's look.
public struct InspectorView: View {
    @Bindable var editor: EditorModel
    let clicks: [Click]
    let useForNewTakes: (Look) -> Void
    @State private var name = ""
    static let swatchNames = ["#3E4A4F": "Slate", "#D9CFC0": "Sand", "#1F2A44": "Navy", "#F2F2F2": "White", "#7A3B2E": "Brick"]
    @FocusState private var naming: Bool
    @Environment(\.dollyShot) private var shot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var savedDefault = false

    public init(editor: EditorModel, clicks: [Click], useForNewTakes: @escaping (Look) -> Void) {
        self.editor = editor
        self.clicks = clicks
        self.useForNewTakes = useForNewTakes
    }

    public var body: some View {
        Group {
            if shot {
                content.frame(minHeight: 0, maxHeight: .infinity, alignment: .top).clipped()
            } else {
                ScrollView { content }.scrollIndicators(.never)
            }
        }
        .font(Theme.Font.body)
        .foregroundStyle(Theme.ink.color)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let id = editor.selection, let zoom = editor.zoom(id) {
                zoomSection(zoom)
                Rectangle().fill(Theme.border.color).frame(height: 1).padding(.vertical, 12)
            }
            lookSection
        }
        .padding(16)
    }

    private func zoomSection(_ zoom: Zoom) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Rectangle().fill(Theme.tape.color).frame(width: 18, height: 10)
                Text(editor.zoomCountText).font(Theme.Font.display(16)).accessibilityAddTraits(.isHeader)
            }
            if shot { ShotControls.field(zoom.name) } else {
            TextField("Zoom name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($naming)
                .onAppear { name = zoom.name }
                // Switching zooms mid-edit keeps what was typed for the one being left.
                .onChange(of: zoom.id) { old, _ in
                    if naming, let left = editor.zoom(old), name != left.name { editor.rename(old, name) }
                    name = zoom.name
                }
                .onChange(of: zoom.name) { if !naming { name = zoom.name } }
                .onSubmit { editor.rename(zoom.id, name) }
                .onChange(of: naming) { if !naming, name != zoom.name { editor.rename(zoom.id, name) } }
            }
            Text(InspectorModel.subtitle(zoom, clicks: clicks))
                .font(Theme.Font.body).monospacedDigit().foregroundStyle(Theme.muted.color)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                if shot {
                    ShotControls.segmented(["Hold on the click", "Follow pointer"], selected: zoom.mode == .hold ? 0 : 1)
                } else {
                    Picker("Aim", selection: Binding(get: { zoom.mode }, set: { editor.setMode(zoom.id, $0) })) {
                        Text("Hold on the click").tag(Zoom.Mode.hold)
                        Text("Follow pointer").tag(Zoom.Mode.follow)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            .padding(.vertical, 4)
            row("Depth", InspectorModel.depthText(zoom.depth))
            if shot { ShotControls.slider(fraction: (zoom.depth - 1) / 2) } else {
                Slider(value: Binding(get: { zoom.depth }, set: { editor.setDepth(zoom.id, ($0 * 10).rounded() / 10) }),
                       in: EditorModel.depthRange, step: 0.1) { editing in
                    editing ? editor.beginGesture() : editor.endGesture()
                }
                .tint(Theme.ink.color)
                .accessibilityLabel("Depth")
                .accessibilityValue(InspectorModel.depthText(zoom.depth))
            }
            HStack {
                ForEach(["1×", "2×", "3×"], id: \.self) { tick in
                    Text(tick).font(Theme.Font.tick).foregroundStyle(Theme.muted.color)
                    if tick != "3×" { Spacer() }
                }
            }
            stepper("Move in", value: zoom.moveIn) { editor.setMove(zoom.id, moveIn: $0, moveOut: nil) }
            stepper("Move out", value: zoom.moveOut) { editor.setMove(zoom.id, moveIn: nil, moveOut: $0) }
            HStack {
                Button { editor.remove(zoom.id) } label: {
                    Text("Remove this zoom").underline().foregroundStyle(Theme.muted.color)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("⌫").font(Theme.Font.meta).foregroundStyle(Theme.muted.color)
            }
            .padding(.top, 4)
        }
    }

    private var lookSection: some View {
        let look = editor.take.look
        return VStack(alignment: .leading, spacing: 4) {
            Text("Look").font(.system(size: 13, weight: .semibold)).accessibilityAddTraits(.isHeader)
            HStack {
                Text("Background")
                Spacer()
                HStack(spacing: 6) {
                    ForEach(Look.backgrounds, id: \.self) { hex in
                        swatch(hex, selected: look.background == .color(hex: hex)) {
                            var next = look
                            next.background = .color(hex: hex)
                            editor.setLook(next)
                        }
                    }
                }
            }
            .frame(minHeight: 32)
            lookStepper("Padding", text: InspectorModel.pointsText(look.padding), value: look.padding, range: 0...160, step: 8) { $0.padding = $1 }
            lookStepper("Corners", text: InspectorModel.pointsText(look.corners), value: look.corners, range: 0...24, step: 2) { $0.corners = $1 }
            lookToggle("Shadow", look.shadow) { $0.shadow = $1 }
            lookStepper("Pointer size", text: InspectorModel.depthText(look.pointerScale), value: look.pointerScale, range: 1...3, step: 0.25) {
                $0.pointerScale = $1
            }
            lookToggle("Smooth pointer path", look.smoothPointer) { $0.smoothPointer = $1 }
            lookToggle("Ring on each click", look.clickRing) { $0.clickRing = $1 }
            lookToggle("Hide when still", look.hideWhenStill) { $0.hideWhenStill = $1 }
            Button {
                useForNewTakes(look)
                withAnimation(reduceMotion ? nil : .easeOut(duration: Theme.Motion.saved)) { savedDefault = true }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(reduceMotion ? nil : .easeOut(duration: Theme.Motion.saved)) { savedDefault = false }
                }
            } label: {
                ZStack {
                    Text("Use for new takes").opacity(savedDefault ? 0 : 1)
                    Text("Saved for new takes").opacity(savedDefault ? 1 : 0)
                }
            }
            .buttonStyle(DollyButtonStyle())
            .padding(.top, 6)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Theme.Font.bodyMedium)
            Spacer()
            Text(value).monospacedDigit()
        }
        .frame(minHeight: 24)
    }

    @ViewBuilder
    private func stepper(_ label: String, value: Double, set: @escaping (Double) -> Void) -> some View {
        if shot { HStack { row(label, InspectorModel.secondsText(value)); ShotControls.stepper() } } else {
        Stepper(value: Binding(get: { value }, set: { set(($0 * 10).rounded() / 10) }), in: EditorModel.moveRange, step: 0.1) {
            row(label, InspectorModel.secondsText(value))
        }
        }
    }

    @ViewBuilder
    private func lookStepper(_ label: String, text: String, value: Double, range: ClosedRange<Double>, step: Double,
                             apply: @escaping (inout Look, Double) -> Void) -> some View {
        if shot { HStack { row(label, text); ShotControls.stepper() } } else {
        Stepper(value: Binding(get: { value }, set: { v in
            var next = editor.take.look
            apply(&next, v)
            editor.setLook(next)
        }), in: range, step: step) { row(label, text) }
        }
    }

    @ViewBuilder
    private func lookToggle(_ label: String, _ isOn: Bool, apply: @escaping (inout Look, Bool) -> Void) -> some View {
        if shot {
            HStack { Text(label).font(Theme.Font.bodyMedium); Spacer(); ShotControls.toggle(isOn) }.frame(minHeight: 26)
        } else {
        Toggle(isOn: Binding(get: { isOn }, set: { v in
            var next = editor.take.look
            apply(&next, v)
            editor.setLook(next)
        })) { Text(label).font(Theme.Font.bodyMedium) }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .tint(Theme.ink.color)
        .frame(minHeight: 26)
        }
    }

    private func swatch(_ hex: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: ThemeRGBA(hex: UInt32(hex.dropFirst(), radix: 16) ?? 0).nsColor))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.control.color, lineWidth: hex == "#F2F2F2" ? 1 : 0))
                .frame(width: 22, height: 22)
                .padding(2)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Theme.ink.color : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Self.swatchNames[hex] ?? "Custom") background")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
