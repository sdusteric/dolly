import CoreGraphics
import Testing
@testable import DollyCore

@Suite struct RecordingPlanTests {
    @Test func displayPlanUsesDollyValues() throws {
        let p = try RecordingPlan.make(target: .display, displayID: 1, windowID: nil,
                                       globalRect: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
        #expect(p.fps == 60 && p.queueDepth == 6 && !p.showsCursor)
        #expect(p.pixelSize == PixelSize(width: 2880, height: 1800))
        #expect(p.size == CGSize(width: 1440, height: 900))
        #expect(RecordingPlan.fragmentInterval == 2 && RecordingPlan.maxSeconds == 1800 && RecordingPlan.warnSeconds == 300)
    }

    @Test func pixelSizeRoundsDownToEven() throws {
        let p = try RecordingPlan.make(target: .area, displayID: 1, windowID: nil,
                                       globalRect: CGRect(x: 10, y: 10, width: 333.5, height: 201), scale: 1)
        #expect(p.pixelSize == PixelSize(width: 332, height: 200))
    }

    @Test func refusesTinyAreas() {
        #expect(throws: RecordingPlanError.tooSmall) {
            try RecordingPlan.make(target: .area, displayID: 1, windowID: nil, globalRect: CGRect(x: 0, y: 0, width: 40, height: 300), scale: 1)
        }
    }

    @Test func geometryMatchesThePlan() throws {
        let p = try RecordingPlan.make(target: .area, displayID: 1, windowID: nil,
                                       globalRect: CGRect(x: 100, y: 200, width: 800, height: 600), scale: 1)
        #expect(p.geometry(windowFrames: []).toRecording(CGPoint(x: 500, y: 500), at: 0) == CGPoint(x: 400, y: 300))
    }
}
