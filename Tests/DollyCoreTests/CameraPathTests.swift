import CoreGraphics
import Testing
@testable import DollyCore

@Suite struct CameraPathTests {
    let shelfLayout = ShapeLayout(shape: .wide16x9, recordingSize: CGSize(width: 848, height: 858), padding: 64)
    let displayLayout = ShapeLayout(shape: .wide16x9, recordingSize: CGSize(width: 1440, height: 900), padding: 64)

    func shelfPath() throws -> CameraPath {
        let clicks = ClickDetector.clicks(from: try Fixtures.shelfDemoSamples(), geometry: Fixtures.shelfGeometry,
                                          recordingStartHost: 0, stopRequestHost: 48.2)
        let zooms = ZoomRules().zooms(for: clicks, size: CGSize(width: 848, height: 858), target: .window, trim: 0...48.2)
        return CameraPath(zooms: zooms, layout: shelfLayout, pointer: nil, duration: 48.2)
    }

    func zoom(_ start: Double, _ end: Double, depth: Double, aim: CGPoint, mode: Zoom.Mode = .hold) -> Zoom {
        Zoom(start: start, end: end, aim: aim, depth: depth, mode: mode, moveIn: 0.6, moveOut: 0.5, source: .manual, clickIDs: [], name: "")
    }

    @Test func restsAtOneXOutsideZooms() throws {
        let rest = CameraState(depth: 1, center: CGPoint(x: shelfLayout.recordingRect.midX, y: shelfLayout.recordingRect.midY))
        #expect(try shelfPath().camera(at: 0.5) == rest)
        #expect(try shelfPath().camera(at: 46) == rest)
    }

    @Test func holdsOnTheClick() throws {
        let c = try shelfPath().camera(at: 8.5)
        #expect(c.depth == 1.6)
        #expect(approx(c.center, shelfLayout.canvasPoint(CGPoint(x: 636, y: 318)), tol: 0.5))
    }

    @Test func movesInWithTheCurve() throws {
        #expect(approx(try shelfPath().camera(at: 7.6).depth, 1 + 0.6 * Easing.inOut(0.5)))
    }

    @Test func cornerClickClampsView() {
        let path = CameraPath(zooms: [zoom(1, 5, depth: 2, aim: .zero)], layout: displayLayout, pointer: nil, duration: 10)
        let view = displayLayout.viewRect(path.camera(at: 3.0))
        #expect(displayLayout.recordingRect.insetBy(dx: -0.01, dy: -0.01).contains(view))
        #expect(approx(view.minX, displayLayout.recordingRect.minX) && approx(view.minY, displayLayout.recordingRect.minY))
    }

    @Test func overlappingZoomBlendsFromCurrentCamera() {
        let path = CameraPath(zooms: [zoom(1.0, 4.0, depth: 2, aim: CGPoint(x: 300, y: 300)),
                                      zoom(3.7, 7.0, depth: 2, aim: CGPoint(x: 1000, y: 600))],
                              layout: displayLayout, pointer: nil, duration: 10)
        let depths = stride(from: 3.5, through: 5.0, by: 0.01).map { path.camera(at: $0).depth }
        #expect(depths.min()! > 1.4)   // never drops back toward 1x
        #expect(approx(path.camera(at: 3.7).depth, path.camera(at: 3.7 - 1e-4).depth, tol: 0.01))   // no jump
        #expect(approx(path.camera(at: 5.0).center, displayLayout.canvasPoint(CGPoint(x: 1000, y: 600)), tol: 0.5))
    }

    @Test func followStaysStillInsideDeadZone() {
        let aim = CGPoint(x: 720, y: 450)
        let wiggle: @Sendable (Double) -> CGPoint? = { t in CGPoint(x: 720 + 20 * sin(t * 9), y: 450) }
        let path = CameraPath(zooms: [zoom(1, 9, depth: 2, aim: aim, mode: .follow)], layout: displayLayout, pointer: wiggle, duration: 10)
        #expect(approx(path.camera(at: 3).center, path.camera(at: 6).center, tol: 0.01))
    }

    @Test func followMovesWhenPointerLeaves() {
        let jump: @Sendable (Double) -> CGPoint? = { t in t < 3 ? CGPoint(x: 720, y: 450) : CGPoint(x: 1300, y: 450) }
        let path = CameraPath(zooms: [zoom(1, 9, depth: 2, aim: CGPoint(x: 720, y: 450), mode: .follow)],
                              layout: displayLayout, pointer: jump, duration: 10)
        let before = path.camera(at: 2.9).center.x, after = path.camera(at: 6).center.x
        #expect(after > before + 200)
        let view = displayLayout.viewRect(path.camera(at: 6))
        #expect(view.contains(displayLayout.canvasPoint(CGPoint(x: 1300, y: 450))))
    }

    @Test func easingEndpoints() {
        #expect(Easing.inOut(0) == 0 && Easing.inOut(1) == 1)
        #expect(approx(Easing.inOut(0.5), 0.729, tol: 0.005))   // the spec's curve is front-loaded
        #expect(Easing.inOut(0.25) < Easing.inOut(0.5) && Easing.inOut(0.5) < Easing.inOut(0.75))
    }
}
