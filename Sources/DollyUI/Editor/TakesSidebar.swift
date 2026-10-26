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

    public static func footer(count: Int, bytes: Int64) -> String {
        guard count > 0 else { return "Takes will live in ~/Movies/Dolly." }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal)
        return "Takes live in ~/Movies/Dolly. \(count) \(count == 1 ? "take" : "takes"), \(size)."
    }
}

/// The takes list on the frame color (spec 6.1): poster, name, length and zooms; the selected take
/// is a neutral grey pill.
struct TakesSidebar: View {
    let rows: [TakeRow]
    let selected: UUID?
    let footer: String
    let poster: (TakeRow) -> Image?
    let select: (TakeRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Takes")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            ForEach(rows) { row in
                Button { select(row) } label: { rowView(row) }
                    .buttonStyle(SidebarRowStyle(selected: row.takeID == selected && row.takeID != nil))
                    .help(row.title)
                    .accessibilityLabel(row.isBroken ? row.title : "\(row.title), \(row.meta)")
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

    private func rowView(_ row: TakeRow) -> some View {
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
                Text(row.title)
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.ink.color)
                    .lineLimit(1)
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
