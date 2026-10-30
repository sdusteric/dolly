import Foundation
import Testing
@testable import DollyCore

@Suite struct InputModelTests {
    @Test func buttonEdges() {
        #expect(ButtonEdges.edges(previous: 0, current: 1) == [.leftDown])
        #expect(ButtonEdges.edges(previous: 1, current: 0) == [.leftUp])
        #expect(ButtonEdges.edges(previous: 1, current: 1).isEmpty)
        #expect(ButtonEdges.edges(previous: 0, current: 3) == [.leftDown, .rightDown])
    }

    @Test func tapBetweenSamplesStillShowsDownOnce() {
        var latch = ButtonLatch()
        latch.down(1)
        latch.up(1)
        let first = latch.sample()
        let second = latch.sample()
        #expect(first == 1)
        #expect(second == 0)
    }

    @Test func heldButtonStaysDownAcrossSamples() {
        var latch = ButtonLatch()
        latch.down(1)
        let first = latch.sample()
        let second = latch.sample()
        latch.up(1)
        let third = latch.sample()
        #expect([first, second, third] == [1, 1, 0])
    }

    @Test func leftAndRightLatchApart() {
        var latch = ButtonLatch()
        latch.down(1)
        latch.down(2)
        latch.up(2)
        let first = latch.sample()
        let second = latch.sample()
        #expect(first == 3)
        #expect(second == 1)
    }

    @Test func clickDetectorSeesALatchedTap() throws {
        var latch = ButtonLatch()
        let idle = latch.sample()
        latch.down(1)
        latch.up(1)
        let tap = latch.sample()
        let after = latch.sample()
        let samples = [idle, tap, after].enumerated().map { i, b in
            PointerSample(t: 10 + Double(i) / 120, x: 100, y: 100, buttons: b, shape: .arrow)
        }
        let clicks = ClickDetector.clicks(from: samples, geometry: bigDisplay, recordingStartHost: 9, stopRequestHost: nil)
        #expect(clicks.count == 1)
        #expect(try #require(clicks.first).isDrag == false)
    }

    @Test func recordHotkeyDefault() {
        let combo = HotkeyCombo.defaultRecord
        #expect(combo.keyCode == 15 && combo.modifiers == 6400)
        #expect(combo.displayString == "⌃⌥⌘R")
    }
}

@Suite struct SettingsStoreTests {
    @Test func missingFileGivesDefaults() throws {
        let store = SettingsStore(url: tempURL("settings.json"))
        let s = try store.load()
        #expect(s.advanced.clickSource == .poll && !s.advanced.pointerShapes)
        #expect(s.hotkey == .defaultRecord)
    }

    @Test func roundTrips() throws {
        let url = tempURL("settings.json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SettingsStore(url: url)
        var s = Settings()
        s.advanced.clickSource = .monitor
        s.advanced.pointerShapes = true
        try store.save(s)
        #expect(try store.load() == s)
    }

    @Test func unknownKeysAndMissingKeysStillLoad() throws {
        let url = tempURL("settings.json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"advanced":{"clickSource":"monitor"},"later":1}"#.utf8).write(to: url)
        let s = try SettingsStore(url: url).load()
        #expect(s.advanced.clickSource == .monitor && !s.advanced.pointerShapes)
    }
}
