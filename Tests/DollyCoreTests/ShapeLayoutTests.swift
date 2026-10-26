import CoreGraphics
import Testing
@testable import DollyCore

@Suite struct ShapeLayoutTests {
    @Test func presetSizes() {
        #expect(ShapePreset.wide16x9.pixelSize == PixelSize(width: 1920, height: 1080))
        #expect(ShapePreset.tall9x16.pixelSize == PixelSize(width: 1080, height: 1920))
        #expect(ShapePreset.portrait4x5.label == "4:5" && ShapePreset.portrait4x5.fileSuffix == "4x5")
    }

    @Test func layoutFitsShelfDemoIn16x9() {
        let l = ShapeLayout(shape: .wide16x9, recordingSize: CGSize(width: 848, height: 858), padding: 64)
        #expect(approx(l.recordingRect.height, 1080 - 128))
        #expect(approx(l.recordingRect.midX, 960) && approx(l.recordingRect.midY, 540))
        #expect(approx(l.canvasPoint(CGPoint(x: 848, y: 858)), CGPoint(x: l.recordingRect.maxX, y: l.recordingRect.maxY)))
    }

    @Test func paddingScalesWithTheShortSide() {
        let l = ShapeLayout(shape: .square1x1, recordingSize: CGSize(width: 1000, height: 1000), padding: 64)
        #expect(approx(l.recordingRect.minX, 64))
    }

    @Test func narrowAxisCentersInsteadOfClamping() {
        let l = ShapeLayout(shape: .wide16x9, recordingSize: CGSize(width: 848, height: 858), padding: 64)
        let v = l.viewRect(CameraState(depth: 2, center: CGPoint(x: 0, y: 0)))
        #expect(approx(v.midX, l.recordingRect.midX))   // a 960 px view is wider than the 941 px recording
        #expect(approx(v.minY, l.recordingRect.minY))   // but shorter, so it clamps to the top edge
    }
}
