import CoreGraphics
import Foundation
import Testing
@testable import DollyCore
@testable import DollyUI

@Suite struct InspectorModelTests {
    let auto = Zoom(start: 7.3, end: 9.9, aim: .zero, depth: 1.6, mode: .hold, moveIn: 0.6, moveOut: 0.5, source: .auto,
                    clickIDs: [1], name: "Run check up")
    let clicks = [Click(id: 0, t: 2.4, point: .zero), Click(id: 1, t: 7.9, point: .zero)]

    @Test func zoomSubtitle() {
        #expect(InspectorModel.subtitle(auto, clicks: clicks) == "0:07.3 to 0:09.9, 2.6 s.\nFrom your click at 0:07.9.")
    }

    @Test func manualZoomSubtitle() {
        var manual = auto
        manual.source = .manual
        manual.clickIDs = []
        #expect(InspectorModel.subtitle(manual, clicks: clicks) == "0:07.3 to 0:09.9, 2.6 s.\nAdded by you.")
    }

    @Test func valueTexts() {
        #expect(InspectorModel.depthText(1.6) == "1.6×")
        #expect(InspectorModel.secondsText(0.6) == "0.6 s")
        #expect(InspectorModel.pointsText(64) == "64 pt")
    }

    @Test func useForNewTakesSavesDefaultLook() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "dolly-settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SettingsStore(url: url)
        var look = Look()
        look.padding = 96
        look.background = .color(hex: "#D9CFC0")
        try InspectorModel.useForNewTakes(look, store: store)
        #expect(try store.load().defaultLook == look)
    }
}
