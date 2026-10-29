import CoreGraphics
import Foundation
import Testing
@testable import DollyCore
@testable import DollyUI

@MainActor @Suite struct StudioTimelineTests {
    var layout: TimelineLayout { TimelineLayout(width: 1100, duration: 48.2) }
    let captions = SyntheticTake.shelfCaptions().items

    func editor() -> EditorModel {
        var take = SyntheticTake.shelfDemo()
        take.camera = CameraTrack(startOffset: 0)
        take.captions = SyntheticTake.shelfCaptions()
        return EditorModel(take: take, pointer: nil)
    }

    @Test func lanesStackInOrder() {
        let lanes = [TimelineLayout.videoLane, TimelineLayout.zoomLane, TimelineLayout.cameraLane, TimelineLayout.captionLane,
                     TimelineLayout.clickLane]
        #expect(lanes.map(\.height) == [44, 46, 26, 30, 18])
        for (a, b) in zip(lanes, lanes.dropFirst()) { #expect(a.maxY < b.minY) }
        #expect(TimelineLayout.height == TimelineLayout.clickLane.maxY)
    }

    @Test func hitsCaptionChipEdgesAndBody() {
        let fourth = captions[3]
        let chip = layout.chip(for: fourth)
        let y = TimelineLayout.captionLane.midY
        func hit(_ x: CGFloat) -> TimelineHit { layout.hit(CGPoint(x: x, y: y), zooms: [], captions: captions) }
        #expect(hit(chip.minX + 4) == .caption(fourth.id, .startEdge))
        #expect(hit(chip.maxX - 5) == .caption(fourth.id, .endEdge))
        #expect(hit(chip.midX) == .caption(fourth.id, .body))
        guard case .emptyCaptionLane(let t) = hit(layout.x(for: 11.2)) else { Issue.record("no empty lane hit"); return }
        #expect(abs(t - 11.2) < 0.001)
    }

    @Test func cameraLaneHits() {
        var camera = CameraTrack(startOffset: 0)
        camera.hidden = [33...36.5]
        let y = TimelineLayout.cameraLane.midY
        func hit(_ t: Double, dx: CGFloat = 0) -> TimelineHit { layout.hit(CGPoint(x: layout.x(for: t) + dx, y: y), zooms: [], camera: camera) }
        guard case .cameraBar(let t) = hit(20) else { Issue.record("no bar hit"); return }
        #expect(abs(t - 20) < 0.001)
        #expect(hit(33, dx: 3) == .cameraGap(0, .startEdge))
        #expect(hit(36.5, dx: -3) == .cameraGap(0, .endEdge))
        #expect(hit(35) == .cameraGap(0, .body))
        #expect(layout.hit(CGPoint(x: 100, y: y), zooms: []) == .none)   // no camera, nothing to hit
    }

    @Test func dragOnCameraBarHidesARange() {
        let m = editor()
        TimelineInput.finishDrag(.cameraBar(33), from: 33, to: 36.5, moved: true, editor: m)
        #expect(m.take.camera?.hidden == [33...36.5])
        TimelineInput.finishDrag(.cameraGap(0, .body), from: 34, to: 34, moved: false, editor: m)
        #expect(m.take.camera?.hidden == [])
        TimelineInput.finishDrag(.cameraBar(10), from: 10, to: 10, moved: false, editor: m)
        #expect(m.selection == .camera && m.playhead == 10)
    }

    @Test func cKeyAddsCaption() {
        #expect(TimelineInput.action(key: "c", shift: false, command: false) == .addCaption)
        #expect(TimelineInput.action(key: "c", shift: false, command: true) == nil)
        let m = editor()
        m.playhead = 48.0
        TimelineInput.apply(.addCaption, to: m, playback: nil)
        #expect(m.take.captions?.items.count == 10)
        let typed = EditorModel(take: SyntheticTake.shelfDemo(), pointer: nil)
        typed.playhead = 2
        TimelineInput.apply(.addCaption, to: typed, playback: nil)
        #expect(typed.take.captions?.items.count == 1)
    }

    @Test func deleteRemovesTheSelectedCaption() {
        let m = editor()
        m.selectCaption(captions[3].id)
        TimelineInput.apply(.removeSelected, to: m, playback: nil)
        #expect(m.take.captions?.items.count == 9 && m.selection == nil)
    }

    @Test func captionChipLabel() {
        #expect(TimelineAccessibility.label(captions[3], index: 3, count: 10)
            == "Caption 4 of 10, 0:11.4 to 0:14.6, Each tile has its own quick actions.")
    }
}
