import CoreGraphics
import Foundation
import Testing
@testable import DollyCore

@Suite struct OverlayLayoutTests {
    func wide(_ camera: CameraTrack?, caption: CaptionPosition = .bottom) -> OverlayLayout {
        OverlayLayout(canvas: CGSize(width: 1920, height: 1080), recordingRect: CGRect(x: 420, y: 64, width: 1080, height: 952),
                      padding: 64, camera: camera, captionPosition: caption, captionHeight: 60)
    }

    @Test func bubbleSitsInItsCornerAtTheShortSideFraction() throws {
        let b = try #require(wide(CameraTrack(startOffset: 0)).bubble(at: 0))
        #expect(approx(b.width, 1080 * 0.22) && b.height == b.width)
        #expect(approx(b.minX, 38.4) && approx(b.maxY, 1080 - 38.4))   // margin 0.6 * 64 at 1080
    }

    @Test func shrinkDuringZoomsReaches60Percent() throws {
        let o = wide(CameraTrack(startOffset: 0))
        let rest = try #require(o.bubble(at: 0)), deep = try #require(o.bubble(at: 1))
        #expect(approx(deep.width, 0.6 * rest.width))
        #expect(approx(deep.minX, rest.minX) && approx(deep.maxY, rest.maxY))
        var still = CameraTrack(startOffset: 0)
        still.shrinkDuringZooms = false
        #expect(approx(try #require(wide(still).bubble(at: 1)).width, rest.width))
    }

    @Test func draggedPointWinsOverCorner() throws {
        var camera = CameraTrack(startOffset: 0)
        camera.corner = .topRight
        camera.point = CGPoint(x: 0.5, y: 0.5)
        let b = try #require(wide(camera).bubble(at: 0))
        #expect(approx(b.midX, 960) && approx(b.midY, 540))
        camera.point = CGPoint(x: 1, y: 1)
        let edge = try #require(wide(camera).bubble(at: 0))
        #expect(edge.maxX <= 1920 && edge.maxY <= 1080)
    }

    @Test func noCameraNoBubble() {
        #expect(wide(nil).bubble(at: 0) == nil)
    }

    @Test func hiddenRangesHide() {
        var camera = CameraTrack(startOffset: 0)
        camera.hidden = [3...5]
        #expect(camera.isVisible(at: 2.9))
        #expect(!camera.isVisible(at: 4))
        #expect(camera.isVisible(at: 5.01))
    }

    @Test func m1TakeHasNoCamera() throws {
        let take = try JSONDecoder().decode(Take.self, from: Data(m1TakeJSON().utf8))
        #expect(take.camera == nil)
    }

    @Test func bottomCaptionClearsBottomCamera() throws {
        let tall = CGSize(width: 1080, height: 1920)
        let rect = CGRect(x: 38, y: 400, width: 1004, height: 1120)
        let o = OverlayLayout(canvas: tall, recordingRect: rect, padding: 64, camera: CameraTrack(startOffset: 0),
                              captionPosition: .bottom, captionHeight: 80)
        let caption = o.captionRect(width: 900)
        for p in [0.0, 0.5, 1.0] {
            let bubble = try #require(o.bubble(at: p))
            #expect(caption.maxY <= bubble.minY - 10)
            #expect(CGRect(origin: .zero, size: tall).contains(bubble))
        }
        #expect(caption.minY >= 0 && approx(caption.midX, 540))

        var top = CameraTrack(startOffset: 0)
        top.corner = .topLeft
        let up = OverlayLayout(canvas: tall, recordingRect: rect, padding: 64, camera: top, captionPosition: .bottom, captionHeight: 80)
        #expect(approx(up.captionRect(width: 900).maxY, 1920 - 38.4))
        let none = OverlayLayout(canvas: tall, recordingRect: rect, padding: 64, camera: nil, captionPosition: .bottom, captionHeight: 80)
        #expect(approx(none.captionRect(width: 900).maxY, 1920 - 38.4))
    }

    @Test func topAndMiddleCaptions() {
        #expect(approx(wide(nil, caption: .top).captionRect(width: 600).minY, 38.4))
        #expect(approx(wide(nil, caption: .middle).captionRect(width: 600).midY, 540))
    }
}
