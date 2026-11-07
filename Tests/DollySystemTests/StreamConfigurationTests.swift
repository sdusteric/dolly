import CoreGraphics
import CoreMedia
import Testing
@testable import DollyCore
@testable import DollySystem

@Suite struct StreamConfigurationTests {
    @Test func configurationHidesCursorAt60fps() throws {
        let plan = try RecordingPlan.make(target: .area, displayID: 1, windowID: nil,
                                          globalRect: CGRect(x: 100, y: 100, width: 800, height: 600), scale: 2)
        let c = LiveRecordingSource.streamConfiguration(for: plan, displayFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        #expect(c.showsCursor == false)
        #expect(c.minimumFrameInterval == CMTime(value: 1, timescale: 60))
        #expect(c.queueDepth == 6)
        #expect(c.width == 1600 && c.height == 1200)
        // Area source rects are display-local and top-left: global y 100 to 700 on a 900 pt display is 200 from the top.
        #expect(c.sourceRect == CGRect(x: 100, y: 200, width: 800, height: 600))
    }

    /// System audio: 48 kHz stereo from other apps, never Dolly's own sounds. Off by default.
    @Test func systemAudioCapturesOtherAppsOnly() throws {
        var plan = try RecordingPlan.make(target: .display, displayID: 1, windowID: nil,
                                          globalRect: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 1)
        #expect(!LiveRecordingSource.streamConfiguration(for: plan, displayFrame: plan.globalRect).capturesAudio)
        plan.systemAudio = true
        let c = LiveRecordingSource.streamConfiguration(for: plan, displayFrame: plan.globalRect)
        #expect(c.capturesAudio && c.excludesCurrentProcessAudio && c.sampleRate == 48_000 && c.channelCount == 2)
    }

    @Test func globalFrameFromWindowListFlipsY() {
        let r = PointerSampler.globalFrame(windowListBounds: CGRect(x: 10, y: 50, width: 300, height: 200), mainDisplayHeight: 900)
        #expect(r == CGRect(x: 10, y: 650, width: 300, height: 200))
    }

    @Test func frontWindowSkipsDollyPanelsAndTinyWindows() {
        func entry(_ id: Int, pid: Int, layer: Int = 0, w: Double = 800) -> [String: Any] {
            [kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer,
             kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": w, "Height": 600]]
        }
        // Front to back: the bar (floating, Dolly), the menu bar, a tiny palette, Dolly's editor, then Safari.
        let info = [entry(1, pid: 7, layer: 3), entry(2, pid: 50, layer: 24), entry(3, pid: 20, w: 40), entry(4, pid: 7), entry(5, pid: 20)]
        #expect(WindowCatalog.frontWindowID(in: info, excluding: 7) == 5)
        #expect(WindowCatalog.frontWindowID(in: [], excluding: 7) == nil)
    }
}
