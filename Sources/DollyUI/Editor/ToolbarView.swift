import DollyCore
import SwiftUI

nonisolated public enum TakeFacts {
    /// "Window, 848 × 858 pt, 60 fps, recorded today 10:42".
    public static func line(_ take: Take, now: Date = Date(), calendar: Calendar = .current) -> String {
        let kind = switch take.target {
        case .window: "Window"
        case .area: "Area"
        case .display: "Display"
        }
        let time = take.created.formatted(.dateTime.hour().minute())
        let day: String
        if calendar.isDate(take.created, inSameDayAs: now) {
            day = "today \(time)"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(take.created, inSameDayAs: yesterday) {
            day = "yesterday \(time)"
        } else {
            day = take.created.formatted(.dateTime.month(.abbreviated).day())
        }
        return "\(kind), \(Int(take.size.width)) × \(Int(take.size.height)) pt, \(take.fps) fps, recorded \(day)"
    }
}

/// The toolbar on the frame color (spec 6.1): the take's name and facts, Record and Export.
struct ToolbarView: View {
    let title: String?
    let facts: String?
    let recordShortcut: String
    let canExport: Bool
    let showsWindowControls: Bool
    let record: () -> Void
    let export: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if showsWindowControls {
                // Shot mode draws the traffic lights the real window puts here.
                HStack(spacing: 8) {
                    ForEach([0xFF5F57, 0xFEBC2E, 0x28C840], id: \.self) { hex in
                        Circle().fill(Color(nsColor: ThemeRGBA(hex: UInt32(hex)).nsColor)).frame(width: 12, height: 12)
                    }
                }
                .padding(.leading, 20)
            }
            Spacer().frame(width: showsWindowControls ? Theme.Size.sidebar - 80 : Theme.Size.sidebar)
            if let title {
                Text(title).font(Theme.Font.display(15)).foregroundStyle(Theme.ink.color).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            }
            if let facts {
                Text(facts).font(Theme.Font.body).monospacedDigit().foregroundStyle(Theme.muted.color).lineLimit(1)
            }
            Spacer(minLength: 16)
            Button(action: record) {
                HStack(spacing: 6) { RecordDot(); Text("Record"); ShortcutHint(text: recordShortcut) }
            }
            .buttonStyle(DollyButtonStyle())
            Button(action: export) {
                HStack(spacing: 6) { Text("Export"); ShortcutHint(text: "⌘E") }
            }
            .buttonStyle(DollyButtonStyle(kind: .primary))
            .disabled(!canExport)
            .opacity(canExport ? 1 : 0.4)
        }
        .padding(.trailing, 16)
        .frame(height: Theme.Size.toolbar)
    }
}
