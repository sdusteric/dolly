import CoreGraphics
import Testing
@testable import DollyCore

@Suite struct ClickDetectorTests {
    @Test func shelfDemoHasNineClicks() throws {
        let c = ClickDetector.clicks(from: try Fixtures.shelfDemoSamples(), geometry: Fixtures.shelfGeometry,
                                     recordingStartHost: 0, stopRequestHost: 48.2)
        #expect(approx(c.map(\.t), [2.4, 7.9, 15.2, 17.0, 19.8, 27.6, 29.9, 38.9, 41.2]))
        #expect(approx(c[1].point, CGPoint(x: 636, y: 318)))
        #expect(c.map(\.id) == Array(0..<9))
        #expect(c.allSatisfy { !$0.isDrag })
    }

    @Test func doubleClickIsOneClick() {
        let log = makeLog(presses: [(3.00, 3.08, 500, 500), (3.20, 3.28, 502, 500)], until: 5)
        #expect(ClickDetector.clicks(from: log, geometry: bigDisplay, recordingStartHost: 0, stopRequestHost: 5).count == 1)
    }

    @Test func farApartQuickPressesAreTwoClicks() {
        let log = makeLog(presses: [(3.00, 3.08, 500, 500), (3.20, 3.28, 600, 500)], until: 5)
        #expect(ClickDetector.clicks(from: log, geometry: bigDisplay, recordingStartHost: 0, stopRequestHost: 5).count == 2)
    }

    @Test func longPressIsADrag() throws {
        let log = makeLog(presses: [(5.0, 5.9, 500, 500)], until: 7)
        let c = try #require(ClickDetector.clicks(from: log, geometry: bigDisplay, recordingStartHost: 0, stopRequestHost: 7).first)
        #expect(c.isDrag)
        #expect(approx(c.dragEnd ?? 0, 5.9, tol: 0.01))
    }

    @Test func movedPressIsADrag() throws {
        let log = makeLog(presses: [(5.0, 5.2, 500, 500)], until: 7) { t in
            t >= 5.0 && t < 5.2 ? (Float(500 + (t - 5.0) * 100), 500) : (400, 400)
        }
        let c = try #require(ClickDetector.clicks(from: log, geometry: bigDisplay, recordingStartHost: 0, stopRequestHost: 7).first)
        #expect(c.isDrag)
    }

    @Test func dropsCountdownAndStopClicks() {
        // recording starts at host 1.0 (a press at 0.5 is in the countdown); stop at 49.2 (a press at 48.9 is the stop click)
        let shifted = makeLog(presses: [(0.5, 0.58, 500, 500), (48.9, 48.98, 500, 500)], until: 49.2)
        #expect(ClickDetector.clicks(from: shifted, geometry: bigDisplay, recordingStartHost: 1.0, stopRequestHost: 49.2).isEmpty)
    }

    @Test func rightClicksMakeNoClick() {
        let log = makeLog(presses: [(3.0, 3.08, 500, 500)], until: 5, bit: 2)
        #expect(ClickDetector.clicks(from: log, geometry: bigDisplay, recordingStartHost: 0, stopRequestHost: 5).isEmpty)
    }

    @Test func clickOutsideRecordingIsDropped() {
        let area = RecordingGeometry(target: .area, recordingRect: CGRect(x: 0, y: 0, width: 300, height: 300),
                                     windowFrames: [], size: CGSize(width: 300, height: 300))
        let log = makeLog(presses: [(3.0, 3.08, 500, 500)], until: 5)
        #expect(ClickDetector.clicks(from: log, geometry: area, recordingStartHost: 0, stopRequestHost: 5).isEmpty)
    }

    @Test func timesAreRelativeToRecordingStart() throws {
        let log = makeLog(presses: [(13.0, 13.08, 500, 500)], until: 15)
        let c = try #require(ClickDetector.clicks(from: log, geometry: bigDisplay, recordingStartHost: 10, stopRequestHost: 15).first)
        #expect(approx(c.t, 3.0))
        #expect(approx(c.point, CGPoint(x: 500, y: 400)))
    }
}
