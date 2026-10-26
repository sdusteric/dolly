import DollyCore
import Testing
@testable import DollyUI

@Suite struct AdvancedSettingsTests {
    @Test func readout() {
        #expect(AdvancedSettingsModel.readoutText(lastClickAgo: 0.4, point: (512, 300), source: .poll)
            == "Last click: 0.4 s ago at (512, 300), from polling")
        #expect(AdvancedSettingsModel.readoutText(lastClickAgo: 12.04, point: (5, 9), source: .monitor)
            == "Last click: 12.0 s ago at (5, 9), from the event monitor")
        #expect(AdvancedSettingsModel.readoutText(lastClickAgo: nil, point: nil, source: .poll)
            == "No click yet. Click anywhere to test.")
    }

    @Test func advancedShowsOnlyWithOption() {
        #expect(AdvancedSettingsModel.showsAdvanced(optionHeld: true))
        #expect(!AdvancedSettingsModel.showsAdvanced(optionHeld: false))
    }
}
