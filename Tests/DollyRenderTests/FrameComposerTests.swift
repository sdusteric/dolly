import CoreGraphics
import CoreImage
import Testing
@testable import DollyCore
@testable import DollyRender

@Suite struct FrameComposerTests {
    let size = CGSize(width: 1440, height: 900)
    var layout: ShapeLayout { ShapeLayout(shape: .wide16x9, recordingSize: size, padding: 64) }
    var composer: FrameComposer { FrameComposer(layout: layout, look: Look(), recordingPixelScale: 1) }
    var recording: CIImage { redRecording(size: size, square: CGPoint(x: 636, y: 318)) }

    @Test func outputIsCanvasSized() {
        let out = composer.compose(recording: recording, camera: layout.rest, pointer: nil, ring: nil)
        #expect(out.extent == CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    @Test func backgroundFillsOutsideRecording() {
        let out = composer.compose(recording: recording, camera: layout.rest, pointer: nil, ring: nil)
        #expect(near(pixel(out, 10, 10), 0x3E4A4F))
    }

    @Test func recordingCentered() {
        let out = composer.compose(recording: recording, camera: layout.rest, pointer: nil, ring: nil)
        #expect(near(pixel(out, 960, 540), 0xFF0000))
    }

    @Test func depthTwoAimedAtBlueSquareFillsCenter() {
        let center = layout.canvasPoint(CGPoint(x: 656, y: 338))
        let out = composer.compose(recording: recording, camera: CameraState(depth: 2, center: center), pointer: nil, ring: nil)
        #expect(near(pixel(out, 960, 540), 0x0000FF))
        #expect(near(pixel(out, 960 + 30, 540), 0x0000FF))   // the 40 pt square is about 85 px wide at 2x
        #expect(near(pixel(out, 960 + 60, 540), 0xFF0000))
    }

    @Test func pointerDrawnAtThePoint() {
        let out = composer.compose(recording: recording, camera: layout.rest,
                                   pointer: (CGPoint(x: 100, y: 100), .arrow), ring: nil)
        let tip = layout.canvasPoint(CGPoint(x: 100, y: 100))
        #expect(near(pixel(out, Int(tip.x) + 4, Int(tip.y) + 12), 0x000000, tol: 40))
        let left = pixel(out, Int(tip.x) - 6, Int(tip.y) + 12)   // only the soft shadow reaches here
        #expect(left.r > 220 && left.g < 20 && left.b < 20)
    }

    @Test func ringDrawsWhite() {
        let out = composer.compose(recording: recording, camera: layout.rest, pointer: nil,
                                   ring: (CGPoint(x: 300, y: 300), 0.0))
        let c = layout.canvasPoint(CGPoint(x: 300, y: 300))
        let edge = pixel(out, Int(c.x + 22 * 0.95), Int(c.y))
        #expect(edge.r > 200 && edge.g > 150 && edge.b > 150)
    }
}
