import DollyCore
import DollyRender
import SwiftUI

/// The four tabs of the inspector (studio spec item 2).
nonisolated public enum StudioTab: String, CaseIterable, Sendable {
    case look, zooms, camera, captions

    public var label: String {
        switch self {
        case .look: "Look"
        case .zooms: "Zooms"
        case .camera: "Camera"
        case .captions: "Captions"
        }
    }
}

/// Where a picture backdrop comes from: the recorded display's desktop, or a file the owner picks.
nonisolated public enum BackdropPick: Sendable { case desktop, choose }

/// Transcribing the take's microphone into captions (wired by the app).
nonisolated public enum TranscriptionStatus: Sendable, Hashable { case idle, working, failed(String) }

/// What the inspector asks the app to do. Each defaults to nothing, for shots and tests.
public struct StudioActions {
    public var useForNewTakes: (Look) -> Void = { _ in }
    public var chooseBackdrop: (BackdropPick) -> Void = { _ in }
    public var transcribe: () -> Void = {}
    /// The first drag of a zoom's corners on the stage; the hint is not shown again after it.
    public var aimed: () -> Void = {}
    public var aimHintSeen = false
    public init() {}
}

nonisolated public enum StudioInspectorModel {
    /// A selection opens its tab; clearing it goes back to the tab open before.
    public static func tab(for selection: EditorModel.Selection?, previous: StudioTab) -> StudioTab {
        switch selection {
        case .zoom: .zooms
        case .caption: .captions
        case .camera: .camera
        case nil: previous
        }
    }

    public static func shapeNote(_ shape: ShapePreset, recording: CGSize) -> String {
        let size = shape.pixelSize(recording: recording)
        return "Exports \(size.width) × \(size.height) for X and Threads"
    }

    public static func showsBlur(_ background: Look.Background) -> Bool {
        if case .picture = background { true } else { false }
    }

    public static func percentText(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }

    public static func zoomsHint(count: Int) -> String {
        let n = count == 0 ? "No zooms." : count == 1 ? "1 zoom." : "\(count) zooms."
        return n + " Select a zoom on the timeline or press Z to add one at the playhead."
    }

    public static func captionHeader(index: Int, count: Int) -> String { "Caption \(index + 1) of \(count)" }

    public static func captionTimes(_ c: Caption) -> String { "\(TimeText.clock(c.start)) to \(TimeText.clock(c.end))" }

    public static func languageLine(_ locale: String) -> String {
        let id = Locale(identifier: locale).language.languageCode?.identifier ?? locale
        let name = Locale(identifier: "en_US").localizedString(forLanguageCode: id) ?? locale
        return "\(name), transcribed on this Mac."
    }
}

/// The inspector panel: the tab control, then the open tab. Selecting a zoom, the camera or a
/// caption opens its tab; clearing the selection returns to the tab open before.
public struct StudioInspector: View {
    @Bindable var editor: EditorModel
    let clicks: [Click]
    let actions: StudioActions
    let transcription: TranscriptionStatus
    @State private var tab: StudioTab
    @State private var previous: StudioTab = .look
    @Environment(\.dollyShot) private var shot

    public init(editor: EditorModel, clicks: [Click], actions: StudioActions = StudioActions(),
                transcription: TranscriptionStatus = .idle) {
        self.editor = editor
        self.clicks = clicks
        self.actions = actions
        self.transcription = transcription
        _tab = State(initialValue: StudioInspectorModel.tab(for: editor.selection, previous: .look))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StudioSegmented(StudioTab.allCases, selected: tab, label: \.label, proportional: true) { tab = $0 }
                .accessibilityLabel("Inspector")
            Group {
                switch tab {
                case .look: LookTab(editor: editor, actions: actions)
                case .zooms: ZoomsTab(editor: editor, clicks: clicks)
                case .camera: CameraTab(editor: editor)
                case .captions: CaptionsTab(editor: editor, transcription: transcription, transcribe: actions.transcribe)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
        }
        .padding(16)
        .font(Theme.Font.body)
        .foregroundStyle(Theme.ink.color)
        .onChange(of: editor.selection) { old, new in
            if old == nil { previous = tab }
            tab = StudioInspectorModel.tab(for: new, previous: previous)
        }
    }
}

/// A row of choices on the active tone, the chosen one on a sheet-colored pill (the mockup's tabs,
/// shape bar and pickers). Plain buttons, so it draws the same in shot mode.
struct StudioSegmented<Item: Hashable>: View {
    let items: [Item]
    let selected: Item
    let label: (Item) -> String
    let choose: (Item) -> Void
    var itemPadding: CGFloat = 8
    /// Long and short labels share the spare width equally instead of getting equal slots, so a
    /// long label in a tight row ("Captions" in the 288 pt inspector) keeps the same inset as the rest.
    var proportional = false

    init(_ items: [Item], selected: Item, label: @escaping (Item) -> String, itemPadding: CGFloat = 8,
         proportional: Bool = false, choose: @escaping (Item) -> Void) {
        self.items = items
        self.selected = selected
        self.label = label
        self.itemPadding = itemPadding
        self.proportional = proportional
        self.choose = choose
    }

    var body: some View {
        let row = proportional ? AnyLayout(SegmentRow()) : AnyLayout(HStackLayout(spacing: 0))
        row {
            ForEach(items, id: \.self) { item in
                let on = item == selected
                Button { choose(item) } label: {
                    Text(label(item))
                        .font(on ? Theme.Font.bodyMedium : Theme.Font.body)
                        .foregroundStyle(on ? Theme.ink.color : Theme.muted.color)
                        .lineLimit(1)
                        .padding(.horizontal, itemPadding)
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.segment)
                        .background(RoundedRectangle(cornerRadius: Theme.Size.controlRadius).fill(on ? Theme.sheet.color : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: Theme.Size.controlRadius + 2).fill(Theme.active.color))
    }
}

/// Lays items out at their ideal widths and splits what is left of the row equally among them.
struct SegmentRow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let ideal = sizes.reduce(0) { $0 + $1.width }
        return CGSize(width: max(proposal.width ?? ideal, ideal), height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let spare = max(bounds.width - sizes.reduce(0) { $0 + $1.width }, 0) / CGFloat(max(subviews.count, 1))
        var x = bounds.minX
        for (view, size) in zip(subviews, sizes) {
            let width = size.width + spare
            view.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width
        }
    }
}

/// Inspector rows shared by the studio tabs.
struct StudioRows {
    let shot: Bool

    func header(_ text: String) -> some View {
        Text(text).font(Theme.Font.bodyMedium).accessibilityAddTraits(.isHeader)
    }

    func value(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Theme.Font.bodyMedium)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(Theme.muted.color)
        }
    }

    /// A labeled slider with its value; drags are one undo step.
    @ViewBuilder
    func slider(_ label: String, text: String, value: Double, range: ClosedRange<Double>, step: Double,
                editor: EditorModel, set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            self.value(label, text)
            if shot {
                ShotControls.slider(fraction: (value - range.lowerBound) / (range.upperBound - range.lowerBound))
            } else {
                Slider(value: Binding(get: { value }, set: { set(($0 / step).rounded() * step) }), in: range) { editing in
                    editing ? editor.beginGesture() : editor.endGesture()
                }
                .tint(Theme.ink.color)
                .controlSize(.small)
                .accessibilityLabel(label)
                .accessibilityValue(text)
            }
        }
    }

    @ViewBuilder
    func toggle(_ label: String, _ isOn: Bool, set: @escaping (Bool) -> Void) -> some View {
        if shot {
            HStack { Text(label).font(Theme.Font.bodyMedium); Spacer(); ShotControls.toggle(isOn) }.frame(minHeight: 26)
        } else {
            Toggle(isOn: Binding(get: { isOn }, set: set)) { Text(label).font(Theme.Font.bodyMedium) }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Theme.ink.color)
                .frame(minHeight: 26)
        }
    }

    func link(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(text).underline().foregroundStyle(Theme.muted.color) }
            .buttonStyle(.plain)
    }
}
