import AppKit
import SwiftUI

/// Tape around the window the Record bar will record, so the menu's choice is visible on screen.
/// Click-through, and closed before the countdown, so it never lands in a recording.
@MainActor
public final class WindowHighlight {
    private var panel: NSPanel?

    public init() {}

    public func show(_ frame: CGRect?) {
        guard let frame, frame.width > 0, frame.height > 0 else { return hide() }
        let panel = self.panel ?? Self.makePanel()
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    public func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.contentView = NSHostingView(rootView: WindowHighlightView())
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }
}

public struct WindowHighlightView: View {
    public init() {}

    public var body: some View {
        RoundedRectangle(cornerRadius: Theme.Size.targetRadius)
            .fill(Theme.tape.color.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: Theme.Size.targetRadius)
                .strokeBorder(Theme.tape.color, lineWidth: Theme.Size.targetStroke))
            .accessibilityHidden(true)
    }
}
