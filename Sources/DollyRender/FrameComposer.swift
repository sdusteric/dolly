import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import DollyCore
import Foundation

/// Draws one output frame (spec 7): background, the rounded recording with its shadow, the camera,
/// then the click ring and pointer at a fixed screen size. Canvas coordinates are top-left; Core
/// Image's are bottom-left, so everything goes through `ci(_:)`.
public struct FrameComposer: Sendable {
    public let layout: ShapeLayout
    public let look: Look
    public let recordingPixelScale: Double

    public init(layout: ShapeLayout, look: Look, recordingPixelScale: Double) {
        self.layout = layout
        self.look = look
        self.recordingPixelScale = recordingPixelScale
    }

    /// Pixels per point of the 1080 px reference short side.
    var k: Double { min(layout.canvas.width, layout.canvas.height) / 1080 }
    var canvasRect: CGRect { CGRect(origin: .zero, size: layout.canvas) }

    func ci(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: layout.canvas.height - r.maxY, width: r.width, height: r.height) }

    public func compose(
        recording: CIImage, camera: CameraState, pointer: (point: CGPoint, shape: PointerShape)?,
        ring: (center: CGPoint, progress: Double)?
    ) -> CIImage {
        let rect = ci(layout.recordingRect)
        let source = recording.transformed(by: CGAffineTransform(translationX: -recording.extent.minX, y: -recording.extent.minY))
        let s = rect.width / max(source.extent.width, 1)
        let placed = source.transformed(by: CGAffineTransform(scaleX: s, y: s).concatenating(
            CGAffineTransform(translationX: rect.minX, y: rect.minY)))

        let radius = look.corners * k
        let mask = CIFilter.roundedRectangleGenerator()
        mask.extent = rect
        mask.radius = Float(radius)
        mask.color = .white
        let rounded = placed.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask.outputImage ?? CIImage.empty(),
        ])

        var frame = CIImage(color: Self.color(look.background)).cropped(to: canvasRect)
        if look.shadow {
            let shape = CIFilter.roundedRectangleGenerator()
            shape.extent = rect
            shape.radius = Float(radius)
            shape.color = CIColor(red: 0, green: 0, blue: 0, alpha: 0.28)
            let shadow = (shape.outputImage ?? CIImage.empty())
                .transformed(by: CGAffineTransform(translationX: 0, y: -0.02 * rect.width))
                .applyingGaussianBlur(sigma: 0.04 * rect.width / 2)
            frame = shadow.composited(over: frame)
        }
        frame = rounded.composited(over: frame).cropped(to: canvasRect)

        let view = layout.viewRect(camera)
        let v = ci(view)
        let d = layout.canvas.width / view.width
        var out = frame.transformed(by: CGAffineTransform(translationX: -v.minX, y: -v.minY)
            .concatenating(CGAffineTransform(scaleX: d, y: d))).cropped(to: canvasRect)

        func screen(_ recordingPoint: CGPoint) -> CGPoint {
            let p = layout.canvasPoint(recordingPoint)
            return CGPoint(x: (p.x - view.minX) * d, y: layout.canvas.height - (p.y - view.minY) * d)
        }
        if let ring, look.clickRing, let image = ringImage(progress: ring.progress) {
            let c = screen(ring.center)
            out = image.transformed(by: CGAffineTransform(translationX: c.x - image.extent.width / 2,
                                                          y: c.y - image.extent.height / 2)).composited(over: out)
        }
        if let pointer, let art = PointerArt.image(pointer.shape, unit: k * look.pointerScale * 1.2) {
            let c = screen(pointer.point)
            out = art.image.transformed(by: CGAffineTransform(
                translationX: c.x - art.tip.x, y: c.y - (art.image.extent.height - art.tip.y)
            )).composited(over: out)
        }
        return out.cropped(to: canvasRect)
    }

    private func ringImage(progress: Double) -> CIImage? {
        let scale = 0.95 + (1.6 - 0.95) * progress
        let r = 22 * k * scale, line = 3 * k
        let side = Int((2 * (r + line)).rounded(.up)) + 2
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.85 * (1 - progress)))
        ctx.setLineWidth(line)
        let o = Double(side) / 2
        ctx.strokeEllipse(in: CGRect(x: o - r, y: o - r, width: 2 * r, height: 2 * r))
        return ctx.makeImage().map { CIImage(cgImage: $0) }
    }

    static func color(_ background: Look.Background) -> CIColor {
        switch background {
        case .color(let hex):
            let v = UInt32(hex.dropFirst(), radix: 16) ?? 0x3E4A4F
            return CIColor(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255,
                           colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) ?? CIColor(red: 0.24, green: 0.29, blue: 0.31)
        }
    }
}
