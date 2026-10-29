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
