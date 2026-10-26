import CoreGraphics
import Testing
@testable import DollyCore

@Suite struct RecordingGeometryTests {
    @Test func mapsAreaPointsAndFlipsY() {
        let g = RecordingGeometry(target: .area, recordingRect: CGRect(x: 100, y: 200, width: 800, height: 600),
                                  windowFrames: [], size: CGSize(width: 800, height: 600))
        #expect(g.toRecording(CGPoint(x: 100, y: 800), at: 0) == CGPoint(x: 0, y: 0))
        #expect(g.toRecording(CGPoint(x: 500, y: 500), at: 0) == CGPoint(x: 400, y: 300))
        #expect(g.toRecording(CGPoint(x: 50, y: 500), at: 0) == nil)
    }

    @Test func followsAMovedWindow() {
        let g = RecordingGeometry(target: .window, recordingRect: .zero, windowFrames: [
            WindowFrameSample(t: 0, frame: CGRect(x: 0, y: 0, width: 848, height: 858)),
            WindowFrameSample(t: 5, frame: CGRect(x: 200, y: 100, width: 848, height: 858)),
        ], size: CGSize(width: 848, height: 858))
        #expect(g.toRecording(CGPoint(x: 300, y: 858 + 100 - 50), at: 6) == CGPoint(x: 100, y: 50))
        #expect(g.toRecording(CGPoint(x: 100, y: 858 - 50), at: 1) == CGPoint(x: 100, y: 50))
    }

    @Test func scalesAResizedWindowIntoTheFixedSize() {
        let g = RecordingGeometry(target: .window, recordingRect: .zero, windowFrames: [
            WindowFrameSample(t: 0, frame: CGRect(x: 0, y: 0, width: 848, height: 858)),
            WindowFrameSample(t: 2, frame: CGRect(x: 0, y: 0, width: 1696, height: 1716)),
        ], size: CGSize(width: 848, height: 858))
        #expect(g.toRecording(CGPoint(x: 848, y: 1716 - 100), at: 3) == CGPoint(x: 424, y: 50))
    }
}
