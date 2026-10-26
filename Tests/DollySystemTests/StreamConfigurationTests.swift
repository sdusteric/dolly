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

    @Test func globalFrameFromWindowListFlipsY() {
        let r = PointerSampler.globalFrame(windowListBounds: CGRect(x: 10, y: 50, width: 300, height: 200), mainDisplayHeight: 900)
        #expect(r == CGRect(x: 10, y: 650, width: 300, height: 200))
    }
}
