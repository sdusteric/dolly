import Testing
@testable import DollyCore
@testable import DollyUI

@Suite struct RecordBarModelTests {
    @Test func hotkeyOpensBarWhenIdleAndStopsWhenRecording() {
        #expect(RecordBarModel.hotkey(in: .idle) == .openBar)
        #expect(RecordBarModel.hotkey(in: .failed("x")) == .openBar)
        #expect(RecordBarModel.hotkey(in: .recording(since: 1)) == .stop)
        #expect(RecordBarModel.hotkey(in: .countdown(2)) == .cancelCountdown)
        #expect(RecordBarModel.hotkey(in: .finishing) == .ignore)
    }

    @Test func timerTextAndTooltip() {
        #expect(RecordBarModel.timerText(elapsed: 42.4) == "0:42")
        #expect(RecordBarModel.tooltip(elapsed: 42, shortcut: "⌃⌥⌘R") == "Stop recording (⌃⌥⌘R)")
        #expect(RecordBarModel.tooltip(elapsed: 301, shortcut: "⌃⌥⌘R").hasSuffix("Longer than Threads allows"))
    }

    @Test func barOffersThreeTargetsWindowFirst() {
        #expect(RecordBarModel.targets == [.window, .area, .display])
        #expect(RecordBarModel().target == .window)
        #expect(RecordBarModel.label(.display) == "Display")
    }

    @Test func recordNeedsAWindowWhenTargetIsWindow() {
        var m = RecordBarModel()
        #expect(!m.canRecord)
        m.windowID = 42
        #expect(m.canRecord)
        m.target = .display
        m.windowID = nil
        #expect(m.canRecord)
    }

    @Test func permissionCopy() {
        #expect(PermissionWindowModel.message == "Dolly needs Screen Recording to record your screen. It never records until you press Record.")
    }
}
