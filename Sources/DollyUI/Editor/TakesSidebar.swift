import DollyCore
import SwiftUI

nonisolated public struct TakeRow: Identifiable, Hashable, Sendable {
    public var id: URL { folder }
    public var takeID: UUID?
    public var title: String
    public var meta: String
    public var folder: URL
    public var isBroken: Bool
}

nonisolated public enum TakesSidebarModel {
    public static func rows(_ entries: [TakeEntry]) -> [TakeRow] {
        entries.map { entry in
            switch entry {
            case .ok(let take, let folder):
                let detail = take.exports.isEmpty
                    ? "\(take.zooms.count) \(take.zooms.count == 1 ? "zoom" : "zooms")" : "exported"
                return TakeRow(takeID: take.id, title: take.name, meta: "\(TimeText.short(take.duration)) · \(detail)",
                               folder: folder, isBroken: false)
            case .broken(let folder, let reason):
                return TakeRow(takeID: nil, title: reason, meta: "Right-click to show it in Finder", folder: folder, isBroken: true)
            }
        }
    }

    /// The take to open after `folder` goes to the Trash: the next good one below it, else the one above.
    public static func neighbor(of folder: URL, in entries: [TakeEntry]) -> TakeEntry? {
        let good = entries.filter { if case .ok = $0 { true } else { false } }
        guard let i = good.firstIndex(where: { $0.folder == folder }) else { return good.first }
        return i + 1 < good.count ? good[i + 1] : i > 0 ? good[i - 1] : nil
    }

    public static func footer(count: Int, bytes: Int64) -> String {
        guard count > 0 else { return "Takes will live in ~/Movies/Dolly." }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal)
        return "Takes live in ~/Movies/Dolly.\n\(count) \(count == 1 ? "take" : "takes"), \(size)."
    }
}

/// The takes list on the frame color (spec 6.1): poster, name, length and zooms; the selected take
/// is a neutral grey pill. Right-click a take to rename it, show it in Finder or move it to the
/// Trash; double-click its name to rename it.
struct TakesSidebar: View {
    let rows: [TakeRow]
    let selected: UUID?
    let footer: String
    @Binding var renaming: URL?
    let poster: (TakeRow) -> Image?
    let select: (TakeRow) -> Void
    let rename: (TakeRow, String) -> Void
    let reveal: (TakeRow) -> Void
    let trash: (TakeRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Takes")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            ForEach(rows) { row in
                Group {
                    if renaming == row.folder {
                        rowView(row, editing: true)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(row.takeID == selected && row.takeID != nil ? Theme.active.color : .clear))
                    } else {
                        Button { select(row) } label: { rowView(row, editing: false) }
                            .buttonStyle(SidebarRowStyle(selected: row.takeID == selected && row.takeID != nil))
                            .simultaneousGesture(TapGesture(count: 2).onEnded { if !row.isBroken { renaming = row.folder } })
                            .help(row.title)
                    }
                }
                .contextMenu { menu(row) }
                .accessibilityLabel(row.isBroken ? row.title : "\(row.title), \(row.meta)")
                .accessibilityActions { menu(row) }
                // A new take fades in once per recording (motion gate: occasional, preventing a jarring change).
                .transition(.opacity)
            }
            Spacer(minLength: 0)
            Text(footer)
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.muted.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .frame(width: Theme.Size.sidebar, alignment: .leading)
        .animation(.easeOut(duration: Theme.Motion.stripBridge), value: rows.map(\.folder))
    }

    @ViewBuilder private func menu(_ row: TakeRow) -> some View {
        if !row.isBroken { Button("Rename") { renaming = row.folder } }
        Button("Show in Finder") { reveal(row) }
        Divider()
        Button("Move to Trash") { trash(row) }
    }

    private func rowView(_ row: TakeRow, editing: Bool) -> some View {
        HStack(spacing: 10) {
            Group {
                if let image = poster(row) {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Theme.active.color
                }
            }
            .frame(width: Theme.Size.poster.width, height: Theme.Size.poster.height)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 1) {
                if editing {
                    TakeNameField(title: row.title, done: { name in
                        renaming = nil
                        if let name { rename(row, name) }
                    })
                } else {
                    Text(row.title)
                        .font(Theme.Font.bodyMedium)
                        .foregroundStyle(Theme.ink.color)
                        .lineLimit(1)
                }
                Text(row.meta)
                    .font(Theme.Font.meta)
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted.color)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .contentShape(Rectangle())
    }
}

/// The name being edited in a sidebar row: Return or clicking away keeps it, Esc puts it back.
/// `done` gets nil when nothing changed or the name is blank.
private struct TakeNameField: View {
    let title: String
    let done: (String?) -> Void
    @State private var text = ""
    @State private var finished = false
    @FocusState private var focused: Bool
    @Environment(\.dollyShot) private var shot

    var body: some View {
        Group {
            // A real text field reaches into AppKit, which shot mode must never do.
            if shot {
                Text(title).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("Take name", text: $text).textFieldStyle(.plain)
            }
        }
        .lineLimit(1)
        .font(Theme.Font.bodyMedium)
        .foregroundStyle(Theme.ink.color)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.sheet.color))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border.color, lineWidth: 1))
        .padding(.horizontal, -4)
        .padding(.vertical, -2)
        .focused($focused)
        .onAppear { text = title }
        // Focus after the field is in the window, so the name is ready to type over.
        .task { focused = true }
        .onSubmit { finish(keep: true) }
        .onExitCommand { finish(keep: false) }
        .onChange(of: focused) { if !focused { finish(keep: true) } }
        .accessibilityLabel("Take name")
    }

    private func finish(keep: Bool) {
        guard !finished else { return }
        finished = true
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        done(keep && !name.isEmpty && name != title ? name : nil)
    }
}

/// The selected take is a neutral pill; a press shows the same pill for 120 ms (spec 10.6).
private struct SidebarRowStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(selected || configuration.isPressed ? Theme.active.color : .clear))
            .animation(reduceMotion ? nil : .easeOut(duration: Theme.Motion.press), value: configuration.isPressed)
    }
}
