import DollyCore
import SwiftUI

/// Look (studio spec items 3 and 4): the backdrop library, padding, corners, shadow and the pointer.
struct LookTab: View {
    @Bindable var editor: EditorModel
    let actions: StudioActions
    @Environment(\.dollyShot) private var shot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var savedDefault = false

    static let flatNames = ["#3E4A4F": "Slate gray", "#D9CFC0": "Sand", "#1F2A44": "Navy", "#F2F2F2": "White",
                            "#7A3B2E": "Brick", "#151413": "Near black"]

    private var rows: StudioRows { StudioRows(shot: shot) }

    var body: some View {
        let look = editor.take.look
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if shot { content(look) } else { ScrollView { content(look).padding(.bottom, 12) }.scrollIndicators(.never) }
            }
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
            .clipped()
            // The pinned button sits below a hairline so the scrolled rows above it read as cut, not crowded.
            Rectangle().fill(Theme.control.color).frame(height: 1)
            Button {
                actions.useForNewTakes(editor.take.look)
                withAnimation(reduceMotion ? nil : .easeOut(duration: Theme.Motion.saved)) { savedDefault = true }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(reduceMotion ? nil : .easeOut(duration: Theme.Motion.saved)) { savedDefault = false }
                }
            } label: {
                ZStack(alignment: .leading) {
                    Text("Use for new takes").underline().opacity(savedDefault ? 0 : 1)
                    Text("Saved for new takes").opacity(savedDefault ? 1 : 0)
                }
                .foregroundStyle(Theme.muted.color)
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
    }

    private func content(_ look: Look) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                rows.header("Backdrop")
                swatchRow(Look.flatColors.map(Look.Background.color(hex:)))
                swatchRow(Backdrop.gradients.map { .gradient(id: $0.id) })
                HStack(spacing: 8) {
                    pictureButton("Desktop", .desktop)
                    pictureButton("Choose…", .choose)
                }
                if case .picture(let file, let blur) = look.background {
                    rows.slider("Blur", text: InspectorModel.pointsText(blur), value: blur, range: 0...40, step: 1, editor: editor) {
                        editor.setBackdrop(.picture(file: file, blur: $0))
                    }
                }
            }
            rows.slider("Padding", text: InspectorModel.pointsText(look.padding), value: look.padding, range: 0...160, step: 4,
                        editor: editor) { v in edit { $0.padding = v } }
            rows.slider("Corners", text: InspectorModel.pointsText(look.corners), value: look.corners, range: 0...24, step: 1,
                        editor: editor) { v in edit { $0.corners = v } }
            rows.slider("Shadow", text: StudioInspectorModel.percentText(look.shadow), value: look.shadow, range: 0...1, step: 0.05,
                        editor: editor) { v in edit { $0.shadow = v } }
            VStack(alignment: .leading, spacing: 10) {
                rows.header("Pointer")
                rows.slider("Size", text: InspectorModel.depthText(look.pointerScale), value: look.pointerScale, range: 1...3,
                            step: 0.25, editor: editor) { v in edit { $0.pointerScale = v } }
                rows.toggle("Ring on each click", look.clickRing) { v in edit { $0.clickRing = v } }
                rows.toggle("Smooth path", look.smoothPointer) { v in edit { $0.smoothPointer = v } }
                rows.toggle("Hide when still", look.hideWhenStill) { v in edit { $0.hideWhenStill = v } }
            }
            .padding(.top, 8)
        }
    }

    private func edit(_ body: (inout Look) -> Void) {
        var next = editor.take.look
        body(&next)
        editor.setLook(next)
    }

    private func swatchRow(_ backgrounds: [Look.Background]) -> some View {
        HStack(spacing: 0) {
            ForEach(backgrounds, id: \.self) { background in
                swatch(background)
                if background != backgrounds.last { Spacer(minLength: 4) }
            }
        }
    }

    private func swatch(_ background: Look.Background) -> some View {
        let selected = editor.take.look.background == background
        let radius = Theme.Size.controlRadius
        return Button { editor.setBackdrop(background) } label: {
            BackdropSwatch(background: background)
                .frame(width: Theme.Size.swatch, height: Theme.Size.swatch)
                .clipShape(RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.border.color, lineWidth: 1))
                .padding(2)
                .overlay(RoundedRectangle(cornerRadius: radius + 2).strokeBorder(selected ? Theme.ink.color : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.name(background) + " backdrop")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    static func name(_ background: Look.Background) -> String {
        switch background {
        case .color(let hex): flatNames[hex] ?? "Custom"
        case .gradient(let id): Backdrop.gradient(id)?.name ?? "Gradient"
        case .picture: "Picture"
        }
    }

    private func pictureButton(_ label: String, _ pick: BackdropPick) -> some View {
        Button { actions.chooseBackdrop(pick) } label: {
            Text(label)
                .font(Theme.Font.bodyMedium)
                .frame(maxWidth: .infinity, minHeight: Theme.Size.swatch)
                .overlay(RoundedRectangle(cornerRadius: Theme.Size.controlRadius)
                    .strokeBorder(Theme.control.color, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A backdrop drawn the way the composer draws it, small: a flat color, or a gradient with its light.
struct BackdropSwatch: View {
    let background: Look.Background

    var body: some View {
        switch background {
        case .color(let hex):
            Rectangle().fill(Self.color(hex))
        case .gradient(let id):
            if let g = Backdrop.gradient(id) {
                let a = g.angle * .pi / 180
                // CSS angles: 180 runs down; y grows down in SwiftUI too.
                let dx = sin(a) / 2, dy = -cos(a) / 2
                ZStack {
                    LinearGradient(colors: [Self.color(g.top), Self.color(g.bottom)],
                                   startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy), endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
                    EllipticalGradient(colors: [Self.color(g.light), Self.color(g.light).opacity(0)],
                                       center: UnitPoint(x: g.lightAt.x, y: g.lightAt.y), startRadiusFraction: 0, endRadiusFraction: 0.66)
                }
            } else {
                Rectangle().fill(Self.color(Look.flatColors[0]))
            }
        case .picture:
            Rectangle().fill(Theme.raised.color)
        }
    }

    static func color(_ hex: String) -> Color {
        Color(nsColor: ThemeRGBA(hex: UInt32(hex.dropFirst(), radix: 16) ?? 0).nsColor)
    }
}
