import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import DollyCore
@testable import DollyRender

@Suite struct StillRendererTests {
    func recording(_ size: CGSize) -> CGImage? {
        testContext.createCGImage(redRecording(size: size, square: CGPoint(x: 20, y: 20)), from: CGRect(origin: .zero, size: size))
    }

    /// The Aim still renders at the stage's size, not the export canvas.
    @Test func scaleShrinksTheStill() throws {
        let take = Take(name: "t", target: .window, size: CGSize(width: 800, height: 500), pixelScale: 1, fps: 60, duration: 2)
        let frame = try #require(recording(CGSize(width: 800, height: 500)))
        let full = try #require(StillRenderer.render(take: take, recording: frame, camera: nil, pointer: nil, ring: nil))
        let half = try #require(StillRenderer.render(take: take, recording: frame, camera: nil, pointer: nil, ring: nil, scale: 0.5))
        #expect(full.width == 1920 && full.height == 1080)
        #expect(half.width == 960 && half.height == 540)
    }

    @Test func previewScaleFitsTheStageAndNeverGrows() {
        let canvas = CGSize(width: 1920, height: 1080)
        #expect(StillRenderer.previewScale(canvas: canvas, stagePixels: CGSize(width: 960, height: 540)) == 0.5)
        #expect(StillRenderer.previewScale(canvas: canvas, stagePixels: CGSize(width: 4000, height: 3000)) == 1)
        #expect(StillRenderer.previewScale(canvas: canvas, stagePixels: .zero) == 1)
        // A narrow stage limits by width; the still never drops below a quarter of the canvas.
        #expect(StillRenderer.previewScale(canvas: canvas, stagePixels: CGSize(width: 192, height: 1080)) == 0.25)
    }
}
