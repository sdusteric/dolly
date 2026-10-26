import CoreGraphics
import Testing
@testable import DollyCore

@Suite struct ZoomRulesTests {
    let shelfSize = CGSize(width: 848, height: 858)

    func shelfClicks() throws -> [Click] {
        ClickDetector.clicks(from: try Fixtures.shelfDemoSamples(), geometry: Fixtures.shelfGeometry,
                             recordingStartHost: 0, stopRequestHost: 48.2)
    }

    @Test func shelfDemoMakesFiveZooms() throws {
        let z = ZoomRules().zooms(for: try shelfClicks(), size: shelfSize, target: .window, trim: 0...48.2)
        #expect(z.count == 5)
        #expect(approx(z.map(\.start), [1.8, 7.3, 14.6, 27.0, 38.3]))
        #expect(approx(z.map(\.end), [4.4, 9.9, 21.8, 31.9, 43.2]))
        #expect(z.allSatisfy { $0.depth == 1.6 })
        #expect(z[2].clickIDs.count == 3)
        #expect(z.allSatisfy { $0.source == .auto && $0.moveIn == 0.6 && $0.moveOut == 0.5 })
        #expect(approx(z[1].aim, CGPoint(x: 636, y: 318)))
        #expect(z[1].mode == .hold)
        #expect(z[1].name == "Click at 0:07.9")
    }

    @Test func wideDisplayUsesSpreadDepthAndFollows() {
        let clicks = [Click(id: 0, t: 3.0, point: CGPoint(x: 100, y: 100)), Click(id: 1, t: 4.0, point: CGPoint(x: 1200, y: 700))]
        let z = ZoomRules().zooms(for: clicks, size: CGSize(width: 1440, height: 900), target: .display, trim: 0...10)
        #expect(z.count == 1)
        #expect(z[0].depth == 1.8 && z[0].mode == .follow)
        #expect(approx(z[0].aim, CGPoint(x: 650, y: 400)))
    }

    @Test func singleClickOnWideDisplayIsTwoX() {
        let z = ZoomRules().zooms(for: [Click(id: 0, t: 3.0, point: CGPoint(x: 100, y: 100))],
                                  size: CGSize(width: 1440, height: 900), target: .display, trim: 0...10)
        #expect(z[0].depth == 2.0 && z[0].mode == .hold)
    }

    @Test func zoomsOneSecondApartStaySeparate() {
        let clicks = [Click(id: 0, t: 2.0, point: CGPoint(x: 10, y: 10)), Click(id: 1, t: 5.6, point: CGPoint(x: 20, y: 10))]
        #expect(ZoomRules().zooms(for: clicks, size: CGSize(width: 1440, height: 900), target: .display, trim: 0...10).count == 2)
    }

    @Test func closeZoomsMerge() {
        let clicks = [Click(id: 0, t: 2.0, point: CGPoint(x: 10, y: 10)), Click(id: 1, t: 5.5, point: CGPoint(x: 20, y: 10))]
        let z = ZoomRules().zooms(for: clicks, size: CGSize(width: 1440, height: 900), target: .display, trim: 0...10)
        #expect(z.count == 1)
        #expect(approx(z[0].start, 1.4) && approx(z[0].end, 7.5))
        #expect(z[0].clickIDs == [0, 1])
    }

    @Test func dragFollows() {
        let z = ZoomRules().zooms(for: [Click(id: 0, t: 3.0, point: CGPoint(x: 100, y: 100), isDrag: true, dragEnd: 4.0)],
                                  size: CGSize(width: 1440, height: 900), target: .display, trim: 0...10)
        #expect(z[0].mode == .follow)
    }

    @Test func leadInClampedAtStart() {
        let z = ZoomRules().zooms(for: [Click(id: 0, t: 0.1, point: CGPoint(x: 10, y: 10))],
                                  size: CGSize(width: 1440, height: 900), target: .display, trim: 0...10)
        #expect(z[0].start == 0)
    }

    @Test func endClampedAtTrim() {
        let z = ZoomRules().zooms(for: [Click(id: 0, t: 9.5, point: CGPoint(x: 10, y: 10))],
                                  size: CGSize(width: 1440, height: 900), target: .display, trim: 0...10)
        #expect(z[0].end == 10)
    }

    @Test func noClicksNoZooms() {
        #expect(ZoomRules().zooms(for: [], size: shelfSize, target: .display, trim: 0...9).isEmpty)
    }
}
