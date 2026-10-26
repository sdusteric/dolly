import SwiftUI

/// Dolly's two button looks: a bordered secondary and the one near-black primary (spec 6.1). Press
/// feedback is a 120 ms background change, the family's token; Reduce Motion makes it instant.
struct DollyButtonStyle: ButtonStyle {
    enum Kind { case secondary, primary }
    var kind: Kind = .secondary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.bodyMedium)
            .foregroundStyle(kind == .primary ? Theme.onPrimary.color : Theme.ink.color)
            .padding(.horizontal, 12)
            .frame(height: Theme.Size.controlHeight)
            .background(RoundedRectangle(cornerRadius: Theme.Size.controlRadius).fill(fill(pressed: configuration.isPressed)))
            .overlay(RoundedRectangle(cornerRadius: Theme.Size.controlRadius)
                .strokeBorder(kind == .primary ? Color.clear : Theme.control.color, lineWidth: 1))
            .animation(reduceMotion ? nil : .easeOut(duration: Theme.Motion.press), value: configuration.isPressed)
    }

    private func fill(pressed: Bool) -> Color {
        switch kind {
        case .primary: Theme.primary.color.opacity(pressed ? 0.82 : 1)
        case .secondary: pressed ? Theme.active.color : Theme.sheet.color
        }
    }
}

/// A shortcut hint inside a button, quieter than the label.
struct ShortcutHint: View {
    let text: String
    var body: some View { Text(text).font(Theme.Font.meta).opacity(0.7) }
}

/// The record dot shared by the toolbar, the empty state and the Record bar.
struct RecordDot: View {
    var body: some View { Circle().fill(Theme.record.color).frame(width: 8, height: 8) }
}
