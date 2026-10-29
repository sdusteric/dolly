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

/// Zooms (studio spec item 2): the selected zoom (spec 6.4), or how to pick one.
struct ZoomsTab: View {
    @Bindable var editor: EditorModel
    let clicks: [Click]
    @State private var name = ""
    @FocusState private var naming: Bool
    @Environment(\.dollyShot) private var shot

    var body: some View {
        if let id = editor.selectedZoom, let zoom = editor.zoom(id) {
            if shot { zoomSection(zoom) } else { ScrollView { zoomSection(zoom) }.scrollIndicators(.never) }
        } else {
            Text(StudioInspectorModel.zoomsHint(count: editor.take.zooms.count))
                .foregroundStyle(Theme.muted.color)
                .fixedSize(horizontal: false, vertical: true)
        }
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
}
