import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import DollyCore
@testable import DollyRender

/// A white 848 x 858 image with `text` in black, its baseline-left at `at` (top-left points).
func textImage(_ text: String, at: CGPoint, size: CGSize = CGSize(width: 848, height: 858)) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(origin: .zero, size: size))
    let font = CTFontCreateWithName("Helvetica" as CFString, 24, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
    ]))
    ctx.textPosition = CGPoint(x: at.x, y: size.height - at.y)
    CTLineDraw(line, ctx)
    return ctx.makeImage()!
}

@Suite struct ZoomNamerTests {
    @Test func namesTheButtonUnderTheClick() async {
        let image = textImage("Run check up", at: CGPoint(x: 580, y: 326))
        #expect(await ZoomNamer.text(near: CGPoint(x: 636, y: 318), in: image, pixelScale: 1) == "Run check up")
    }

    @Test func picksTheNearestLine() async {
        let ctxImage = textImage("Far away label", at: CGPoint(x: 40, y: 60))
        #expect(await ZoomNamer.text(near: CGPoint(x: 636, y: 318), in: ctxImage, pixelScale: 1) == nil)
    }

    @Test func fallsBackToClickTime() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "dolly-namer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let movie = folder.appending(path: TakeStore.movieName)
        try await SyntheticTake.writeMovie(seconds: 1, fps: 30, variableRate: false, to: movie)
        let take = Take(name: "t", target: .display, size: CGSize(width: 1440, height: 900), pixelScale: 1, fps: 30, duration: 1)
        let name = await ZoomNamer().name(for: Click(id: 0, t: 0.5, point: CGPoint(x: 700, y: 400)), movie: movie, take: take)
        #expect(name == "Click at 0:00.5")
    }
}
