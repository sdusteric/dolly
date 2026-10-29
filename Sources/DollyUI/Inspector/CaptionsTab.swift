import DollyCore
import SwiftUI

/// Captions (studio spec, Captions tab): where they come from, the selected caption's words and
/// times, and how every caption draws.
struct CaptionsTab: View {
    @Bindable var editor: EditorModel
    let transcription: TranscriptionStatus
    let transcribe: () -> Void
    @Environment(\.dollyShot) private var shot
    @State private var text = ""
    @State private var cursor: TextSelection?
    @FocusState private var editing: Bool

    static let empty = "No captions yet. Press C to add one at the playhead."
    static let pickOne = "Select a caption on the timeline to change its words."
    static let cameraNote = "Captions move above the camera when both sit at the bottom."
    static let splitHint = "Return splits a caption"
    static let working = "Transcribing…"

    private var rows: StudioRows { StudioRows(shot: shot) }
    private var hasVoice: Bool { editor.take.microphoneOffset != nil }

    private var selected: (index: Int, caption: Caption)? {
        guard case .caption(let id) = editor.selection, let items = editor.take.captions?.items,
              let i = items.firstIndex(where: { $0.id == id }) else { return nil }
        return (i, items[i])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                source
                if let track = editor.take.captions {
                    captionEditor(track)
                    StudioSegmented(CaptionPosition.allCases, selected: track.position, label: { $0.rawValue.capitalized }) { p in
                        editor.setCaptionStyle { $0.position = p }
                    }
                    rows.slider("Size", text: InspectorModel.pointsText(track.size), value: track.size, range: CaptionTrack.sizeRange,
                                step: 1, editor: editor) { v in editor.setCaptionStyle { $0.size = v } }
                    rows.toggle("Save an .srt file with each export", track.saveSRT) { v in editor.setCaptionStyle { $0.saveSRT = v } }
                    if editor.take.camera != nil {
                        Text(Self.cameraNote).foregroundStyle(Theme.muted.color).fixedSize(horizontal: false, vertical: true)
                    }
                } else if transcription == .idle {
                    Text(Self.empty).foregroundStyle(Theme.muted.color).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            HStack {
                if hasVoice, transcription != .working {
                    rows.link(editor.take.captions == nil ? "Transcribe" : "Transcribe again", action: transcribe)
                }
                Spacer()
                if editor.take.captions != nil {
                    Text(Self.splitHint).font(Theme.Font.meta).foregroundStyle(Theme.muted.color)
                }
            }
        }
    }

    @ViewBuilder private var source: some View {
        if hasVoice {
            let voice = editor.take.captions?.source != .typed
            StudioSegmented(["From your voice", "Typed"], selected: voice ? "From your voice" : "Typed", label: { $0 }) { choice in
                if choice == "Typed" {
                    editor.setCaptionStyle { $0.source = .typed }
                } else if !voice {
                    transcribe()
                }
            }
            switch transcription {
            case .working:
                Text(Self.working).foregroundStyle(Theme.muted.color)
            case .failed(let reason):
                Text("Couldn't transcribe: \(reason)").foregroundStyle(Theme.muted.color).fixedSize(horizontal: false, vertical: true)
            case .idle:
                if voice, let track = editor.take.captions {
                    Text(StudioInspectorModel.languageLine(track.locale)).foregroundStyle(Theme.muted.color)
                }
            }
        }
    }

    @ViewBuilder
    private func captionEditor(_ track: CaptionTrack) -> some View {
        if let (index, caption) = selected {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(StudioInspectorModel.captionHeader(index: index, count: track.items.count)).font(Theme.Font.bodyMedium)
                    Spacer()
                    Text(StudioInspectorModel.captionTimes(caption)).monospacedDigit().foregroundStyle(Theme.muted.color)
                }
                field(caption)
            }
        } else {
            Text(Self.pickOne).foregroundStyle(Theme.muted.color).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func field(_ caption: Caption) -> some View {
        let box = RoundedRectangle(cornerRadius: Theme.Size.controlRadius)
        if shot {
            Text(caption.text)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
                .padding(8)
                .background(box.fill(Theme.sheet.color))
                .overlay(box.strokeBorder(Theme.control.color, lineWidth: 1))
        } else {
            TextField("Caption", text: $text, selection: $cursor, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .focused($editing)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
                .padding(8)
                .background(box.fill(Theme.sheet.color))
                .overlay(box.strokeBorder(editing ? Theme.ink.color : Theme.control.color, lineWidth: 1))
                .onAppear { text = caption.text }
                .onChange(of: caption.id) { old, _ in
                    commit(old)
                    text = caption.text
                }
                .onChange(of: caption.text) { if !editing { text = caption.text } }
                .onChange(of: editing) { if !editing { commit(caption.id) } }
                .onKeyPress(.return) {
                    commit(caption.id)
                    editor.splitCaption(caption.id, at: cursorOffset ?? text.count)
                    return .handled
                }
                .onKeyPress(.delete) {
                    guard cursorOffset == 0 else { return .ignored }
                    commit(caption.id)
                    editor.joinCaption(caption.id)
                    return .handled
                }
                .accessibilityLabel("Caption text")
        }
    }

    /// Where the insertion point is, in characters, when nothing is selected.
    private var cursorOffset: Int? {
        guard case .selection(let range) = cursor?.indices, range.isEmpty, range.lowerBound <= text.endIndex else { return nil }
        return text.distance(from: text.startIndex, to: range.lowerBound)
    }

    private func commit(_ id: Caption.ID) {
        if let current = editor.caption(id), current.text != text { editor.editCaption(id, text: text) }
    }
}
