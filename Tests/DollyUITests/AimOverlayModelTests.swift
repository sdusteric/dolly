import CoreGraphics
import Testing
@testable import DollyCore
@testable import DollyUI

@Suite struct AimOverlayModelTests {
    let take: Take = {
        var t = Take(name: "d", target: .display, size: CGSize(width: 1440, height: 900), pixelScale: 1, fps: 60, duration: 10)
        t.zooms = [Zoom(start: 1, end: 5, aim: CGPoint(x: 700, y: 400), depth: 2, mode: .hold, moveIn: 0.6, moveOut: 0.5,
                        source: .auto, clickIDs: [0], name: "Run check up")]
        return t
    }()
    let clicks = [Click(id: 0, t: 1.6, point: CGPoint(x: 700, y: 400))]
    var model: AimOverlayModel { AimOverlayModel(take: take, clicks: clicks, stageSize: CGSize(width: 960, height: 540)) }
    var zoom: Zoom { take.zooms[0] }

    @Test func viewRectMatchesCameraPathHold() {
        let layout = ShapeLayout(shape: .wide16x9, recordingSize: take.size, padding: take.look.padding)
        let canvas = layout.viewRect(CameraState(depth: 2, center: layout.canvasPoint(zoom.aim)))
        let s = 960.0 / 1920.0
        let v = model.viewRect(for: zoom)
        #expect(abs(v.minX - canvas.minX * s) < 0.01 && abs(v.width - 480) < 0.01 && abs(v.height - 270) < 0.01)
    }

    @Test func moveDragShiftsTheAim() {
        let aim = model.dragMove(zoom, by: CGSize(width: 100, height: 0), snaps: true)
        let layout = ShapeLayout(shape: .wide16x9, recordingSize: take.size, padding: take.look.padding)
        #expect(abs(aim.x - (700 + 100 / (0.5 * layout.scale))) < 0.01 && abs(aim.y - 400) < 0.01)
    }

    @Test func moveDragSnapsToClickWithin12pt() {
        let aim = model.dragMove(zoom, by: CGSize(width: 8, height: 5), snaps: true)
        #expect(aim == CGPoint(x: 700, y: 400))
    }

    @Test func shiftDragDoesNotSnap() {
        let aim = model.dragMove(zoom, by: CGSize(width: 8, height: 5), snaps: false)
        #expect(aim != CGPoint(x: 700, y: 400))
    }

    @Test func cornerDragChangesDepthKeepingOppositeCorner() {
        let v = model.viewRect(for: zoom)
        // Pull the bottom-right corner out until the view is 640 wide: depth 960 / 640 = 1.5.
        let depth = model.dragCorner(zoom, .bottomRight, to: CGPoint(x: v.minX + 640, y: v.minY + 360))
        #expect(abs(depth - 1.5) < 0.01)
    }

    @Test func cornerDragClampsDepth() {
        let v = model.viewRect(for: zoom)
        #expect(model.dragCorner(zoom, .bottomRight, to: CGPoint(x: v.minX + 10, y: v.minY + 6)) == 3.0)
        #expect(model.dragCorner(zoom, .bottomRight, to: CGPoint(x: v.minX + 5000, y: v.minY + 3000)) == 1.0)
    }

    @Test func labelAndHint() {
        #expect(model.label(for: zoom) == "2.0×  Run check up")
        #expect(AimOverlayModel.hint == "Drag inside the corners to re-aim. Drag a corner to change depth.")
    }
}
