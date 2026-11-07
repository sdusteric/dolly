import AppKit
import Testing
@testable import DollyUI

@MainActor @Suite struct KeyablePanelTests {
    /// Review finding 10: the Record bar and area picker are borderless panels, which refuse key
    /// focus by default, so Esc and Return never reached them. Built here, never shown.
    @Test func borderlessPanelTakesKeyFocus() {
        let panel = KeyablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        #expect(panel.canBecomeKey)
    }

    /// The tape around the chosen window must never catch a click or take focus from the bar.
    @Test func windowHighlightIsClickThrough() {
        let panel = WindowHighlight.makePanel()
        #expect(panel.ignoresMouseEvents)
        #expect(!panel.canBecomeKey)
        #expect(panel.level == .floating)
    }
}

@MainActor @Suite struct SheetWindowTests {
    /// Esc on a sheet reaches the window as cancelOperation, whatever the SwiftUI buttons do.
    /// Built here, never shown.
    @Test func escapeRunsTheCancelHandler() {
        let sheet = SheetWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        var cancels = 0
        sheet.onCancel = { cancels += 1 }
        sheet.cancelOperation(nil)
        #expect(cancels == 1)
    }
}
