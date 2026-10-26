import CoreGraphics
import Testing
@testable import DollyCore

@Suite struct PointerPathTests {
    func shelfPath(_ look: Look = Look()) throws -> PointerPath {
        let samples = try Fixtures.shelfDemoSamples()
        let clicks = ClickDetector.clicks(from: samples, geometry: Fixtures.shelfGeometry, recordingStartHost: 0, stopRequestHost: 48.2)
        return PointerPath(samples: samples, geometry: Fixtures.shelfGeometry, clicks: clicks, recordingStartHost: 0, look: look)
    }

    @Test func pinnedToClickPoint() throws {
        #expect(approx(try #require(try shelfPath().position(at: 7.9 + 0.1)), CGPoint(x: 636, y: 318), tol: 0.05))
    }

    @Test func smoothingRemovesJitter() throws {
        let log = makeLog(presses: [], until: 4) { t in (Float(500 + (Int(t * 120) % 2 == 0 ? 2 : -2)), 500) }
        let path = PointerPath(samples: log, geometry: bigDisplay, clicks: [], recordingStartHost: 0, look: Look())
        let xs = stride(from: 2.0, through: 3.0, by: 1.0 / 120).compactMap { path.position(at: $0)?.x }
        #expect(xs.max()! - xs.min()! < 1.0)
    }

    @Test func ringLasts360ms() throws {
        let path = try shelfPath()
        #expect(path.ring(at: 7.9 + 0.35) != nil)
        #expect(path.ring(at: 7.9 + 0.37) == nil)
        #expect(approx(path.ring(at: 7.9 + 0.18)!.progress, 0.5, tol: 0.01))
    }

    @Test func hidesWhenStill() {
        var look = Look()
        look.hideWhenStill = true
        let log = makeLog(presses: [], until: 14) { t in t < 10 ? (Float(300 + t * 10), 300) : (400, 300) }
        let path = PointerPath(samples: log, geometry: bigDisplay, clicks: [], recordingStartHost: 0, look: look)
        #expect(path.position(at: 12.9) != nil)
        #expect(path.position(at: 13.1) == nil)
    }

    @Test func rawWhenSmoothingOff() throws {
        var look = Look()
        look.smoothPointer = false
        let log = makeLog(presses: [], until: 4) { t in (Float(500 + (Int(t * 120) % 2 == 0 ? 2 : -2)), 500) }
        let path = PointerPath(samples: log, geometry: bigDisplay, clicks: [], recordingStartHost: 0, look: look)
        #expect(approx(try #require(path.position(at: 2.0)), CGPoint(x: 502, y: 400)))
    }

    @Test func offRecordingIsHidden() {
        let area = RecordingGeometry(target: .area, recordingRect: CGRect(x: 0, y: 0, width: 300, height: 300),
                                     windowFrames: [], size: CGSize(width: 300, height: 300))
        let log = makeLog(presses: [], until: 2, rest: (500, 500))
        #expect(PointerPath(samples: log, geometry: area, clicks: [], recordingStartHost: 0, look: Look()).position(at: 1) == nil)
    }
}
