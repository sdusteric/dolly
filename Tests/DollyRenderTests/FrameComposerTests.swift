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

    /// A zoom samples the recording's own pixels in one step, so a Retina take keeps its detail
    /// instead of being shrunk to the canvas and blown back up. 1 px stripes alias into a pattern
    /// that only matches when both paths sample the source the same way.
    @Test func zoomSamplesTheRecordingDirectly() {
        let pixels = CGSize(width: size.width * 2, height: size.height * 2)
        let stripes = CIFilter(name: "CIStripesGenerator", parameters: [
            "inputColor0": CIColor.white, "inputColor1": CIColor.black, "inputWidth": 1, "inputCenter": CIVector(x: 0, y: 0),
        ])!.outputImage!.cropped(to: CGRect(origin: .zero, size: pixels))
        let retina = FrameComposer(layout: layout, look: Look(), recordingPixelScale: 2)
        let camera = CameraState(depth: 2, center: layout.rest.center)
        let out = retina.compose(recording: stripes, camera: camera, pointer: nil, ring: nil)
        let rect = retina.ci(layout.recordingRect), view = retina.ci(layout.viewRect(camera))
        let k = rect.width / pixels.width * 2
        let direct = stripes.transformed(by: CGAffineTransform(scaleX: k, y: k).concatenating(
            CGAffineTransform(translationX: (rect.minX - view.minX) * 2, y: (rect.minY - view.minY) * 2)))
            .cropped(to: out.extent)
        let row = (0..<24).map { pixel(out, 948 + $0, 540).r }
        let expected = (0..<24).map { pixel(direct, 948 + $0, 540).r }
        #expect(zip(row, expected).allSatisfy { abs($0 - $1) <= 6 }, "\(row) vs \(expected)")
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

    /// At the preview's 2x the pointer and caption are drawn with twice the pixels, in the same
    /// place and size, so they stay as sharp as the recording.
    @Test func overlaysDrawAtThePreviewDensity() throws {
        let sharp = FrameComposer(layout: layout, look: Look(), recordingPixelScale: 1, detail: 2)
        let a = try #require(sharp.captionRect("Hello there", camera: nil)), b = try #require(composer.captionRect("Hello there", camera: nil))
        #expect(abs(a.minX - b.minX) <= 1 && abs(a.minY - b.minY) <= 1 && abs(a.width - b.width) <= 1 && abs(a.height - b.height) <= 1)
        let tip = layout.canvasPoint(CGPoint(x: 100, y: 100))
        let art = sharp.compose(recording: recording, camera: layout.rest, pointer: (CGPoint(x: 100, y: 100), .arrow), ring: nil)
            .transformed(by: CGAffineTransform(scaleX: 2, y: 2))
        #expect(near(pixel(art, Int(tip.x * 2) + 8, Int(tip.y * 2) + 24), 0x000000, tol: 40))
        // Inside the arrow's white outline there are twice the pixels: a crisp 1 px edge, not a 2 px blur.
        #expect(sharp.pointerUnit > composer.pointerUnit * 1.99)
    }
}
