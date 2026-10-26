import SwiftUI

/// No takes yet (spec 6.5): one sentence and the Record button with its shortcut.
struct EmptyStateView: View {
    static let message = "Record a window, an area or the whole screen. Dolly zooms in where you click."
    let shortcut: String
    let record: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(Self.message)
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink.color)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button(action: record) {
                HStack(spacing: 6) { RecordDot(); Text("Record"); ShortcutHint(text: shortcut) }
            }
            .buttonStyle(DollyButtonStyle(kind: .primary))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
