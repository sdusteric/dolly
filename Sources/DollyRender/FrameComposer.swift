import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import DollyCore
import Foundation

/// Draws one output frame (spec 7, studio spec): the backdrop, the rounded recording with its
/// shadow, the zoom camera, the click ring and pointer at a fixed screen size, then the webcam bubble
/// and the caption in canvas space so neither zooms. Canvas coordinates are top-left; Core Image's
/// are bottom-left, so everything goes through `ci(_:)`.
public struct FrameComposer: Sendable {
    public let layout: ShapeLayout
    public let look: Look
    public let recordingPixelScale: Double
    public let captionPosition: CaptionPosition
    public let captionSize: Double
    let backdrop: CIImage

    /// `backdropImage` is the loaded picture when the look's background is one; without it a picture
    /// backdrop draws the default flat color.
    public init(layout: ShapeLayout, look: Look, recordingPixelScale: Double, backdropImage: CIImage? = nil,
                captionPosition: CaptionPosition = .bottom, captionSize: Double = 15) {
        self.layout = layout
        self.look = look
        self.recordingPixelScale = recordingPixelScale
        self.captionPosition = captionPosition
        self.captionSize = captionSize
        let k = min(layout.canvas.width, layout.canvas.height) / 1080
        backdrop = Self.backdrop(look.background, canvas: CGRect(origin: .zero, size: layout.canvas), k: k, picture: backdropImage)
    }

    /// The composer for `take` as saved in `folder`: a missing picture falls back to the default
    /// color, and the captions keep their position and size.
    public static func make(take: Take, folder: URL?, layout: ShapeLayout) -> FrameComposer {
        let look = folder.map { take.look.resolved(in: $0) } ?? take.look
        var picture: CIImage?
        if case .picture(let file, _) = look.background, let folder {
            picture = CIImage(contentsOf: folder.appending(path: file))
        }
        return FrameComposer(layout: layout, look: look, recordingPixelScale: take.pixelScale, backdropImage: picture,
                             captionPosition: take.captions?.position ?? .bottom, captionSize: take.captions?.size ?? 15)
    }

    /// Pixels per point of the 1080 px reference short side.
    var k: Double { min(layout.canvas.width, layout.canvas.height) / 1080 }
    var canvasRect: CGRect { CGRect(origin: .zero, size: layout.canvas) }

    func ci(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: layout.canvas.height - r.maxY, width: r.width, height: r.height) }

    /// `cameraState` is the webcam track while it shows, with how far into a zoom's depth the camera
    /// is (0 at 1x, 1 at full depth); the bubble needs `cameraFrame` too.
    public func compose(
        recording: CIImage, camera: CameraState, pointer: (point: CGPoint, shape: PointerShape)?,
        ring: (center: CGPoint, progress: Double)?, cameraFrame: CIImage? = nil,
        cameraState: (track: CameraTrack, depthProgress: Double)? = nil, caption: String? = nil
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

        var frame = backdrop
        if look.shadow > 0 {
            let shape = CIFilter.roundedRectangleGenerator()
            shape.extent = rect
            shape.radius = Float(radius)
            // 60 % is the shadow M1 drew.
            shape.color = CIColor(red: 0, green: 0, blue: 0, alpha: 0.28 * min(look.shadow, 1) / 0.6)
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
        let overlay = overlayLayout(camera: cameraState?.track, captionHeight: 0)
        if let state = cameraState, let cameraFrame, let r = overlay.bubble(at: state.depthProgress) {
            out = bubble(cameraFrame, track: state.track, rect: r).composited(over: out)
        }
        if let caption, let art = captionArt(caption) {
            let r = overlayLayout(camera: cameraState?.track, captionHeight: art.extent.height).captionRect(width: art.extent.width)
            out = art.transformed(by: CGAffineTransform(translationX: ci(r).minX - art.extent.minX, y: ci(r).minY - art.extent.minY))
                .composited(over: out)
        }
        return out.cropped(to: canvasRect)
    }

    /// Where `text` draws as a caption, in canvas pixels, top-left origin. `camera` is the webcam
    /// while it shows.
    public func captionRect(_ text: String, camera: CameraTrack?) -> CGRect? {
        guard let art = captionArt(text) else { return nil }
        return overlayLayout(camera: camera, captionHeight: art.extent.height).captionRect(width: art.extent.width)
    }

    func overlayLayout(camera: CameraTrack?, captionHeight: Double) -> OverlayLayout {
        OverlayLayout(canvas: layout.canvas, recordingRect: layout.recordingRect, padding: look.padding, camera: camera,
                      captionPosition: captionPosition, captionHeight: captionHeight)
    }

    func captionArt(_ text: String) -> CIImage? {
        let margin = OverlayLayout.marginFraction * look.padding * k
        return CaptionArt.image(text: text, sizePoints: captionSize, k: k, maxWidth: layout.canvas.width - 2 * max(margin, 16 * k))
    }

    /// The webcam aspect-filled into `rect` (canvas pixels, top-left), mirrored when asked, clipped
    /// to a circle or rounded square inside its white border.
    func bubble(_ frame: CIImage, track: CameraTrack, rect: CGRect) -> CIImage {
        let outer = ci(rect)
        let border = track.border ? OverlayLayout.border * k : 0
        let inner = outer.insetBy(dx: border, dy: border)
        func radius(_ r: CGRect) -> Float { Float(track.shape == .circle ? r.width / 2 : OverlayLayout.roundedRadius * r.width) }

        var source = frame.transformed(by: CGAffineTransform(translationX: -frame.extent.minX, y: -frame.extent.minY))
        let w = max(source.extent.width, 1), h = max(source.extent.height, 1)
        if track.mirror { source = source.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0)) }
        let scale = max(inner.width / w, inner.height / h)
        let placed = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(
            translationX: inner.midX - w * scale / 2, y: inner.midY - h * scale / 2)))
        let mask = CIFilter.roundedRectangleGenerator()
        mask.extent = inner
        mask.radius = radius(inner)
        mask.color = .white
        var out = placed.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask.outputImage ?? CIImage.empty(),
        ]).cropped(to: inner)
        if border > 0 {
            let ring = CIFilter.roundedRectangleGenerator()
            ring.extent = outer
            ring.radius = radius(outer)
            ring.color = .white
            out = out.composited(over: ring.outputImage ?? CIImage.empty())
        }
        return out
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

    static func backdrop(_ background: Look.Background, canvas: CGRect, k: Double, picture: CIImage?) -> CIImage {
        let plain = CIImage(color: color(hex: Look.flatColors[0])).cropped(to: canvas)
        switch background {
        case .color(let hex):
            return CIImage(color: color(hex: hex)).cropped(to: canvas)
        case .gradient(let id):
            guard let g = Backdrop.gradient(id) else { return plain }
            return gradient(g, canvas: canvas)
        case .picture(_, let blur):
            guard let picture, picture.extent.width > 0, picture.extent.height > 0, !picture.extent.isInfinite else { return plain }
            let p = picture.transformed(by: CGAffineTransform(translationX: -picture.extent.minX, y: -picture.extent.minY))
            let s = max(canvas.width / p.extent.width, canvas.height / p.extent.height)
            var filled = p.transformed(by: CGAffineTransform(scaleX: s, y: s).concatenating(CGAffineTransform(
                translationX: (canvas.width - p.extent.width * s) / 2, y: (canvas.height - p.extent.height * s) / 2)))
            // Clamped first, so the blur pulls in the picture's own edge rather than transparent black.
            if blur > 0 { filled = filled.clampedToExtent().applyingGaussianBlur(sigma: blur * k / 2) }
            return filled.cropped(to: canvas).composited(over: plain)
        }
    }

    /// A CSS-style linear gradient at `angle` (180 runs down) with one soft elliptical light, the
    /// same as the mockup's `--bd-*` backgrounds.
    static func gradient(_ g: Backdrop.Gradient, canvas: CGRect) -> CIImage {
        let w = canvas.width, h = canvas.height
        let a = g.angle * .pi / 180
        let dir = CGPoint(x: sin(a), y: cos(a))   // Core Image's y points up.
        let half = (abs(w * sin(a)) + abs(h * cos(a))) / 2
        let linear = CIFilter.linearGradient()
        linear.point0 = CGPoint(x: w / 2 - dir.x * half, y: h / 2 - dir.y * half)
        linear.point1 = CGPoint(x: w / 2 + dir.x * half, y: h / 2 + dir.y * half)
        linear.color0 = color(hex: g.top)
        linear.color1 = color(hex: g.bottom)
        let light = color(hex: g.light)
        let radial = CIFilter.radialGradient()
        radial.center = .zero
        radial.radius0 = 0
        radial.radius1 = 0.55
        radial.color0 = light
        radial.color1 = CIColor(red: light.red, green: light.green, blue: light.blue, alpha: 0, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            ?? CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        let glow = (radial.outputImage ?? CIImage.empty()).transformed(by: CGAffineTransform(scaleX: 1.2 * w, y: 0.9 * h)
            .concatenating(CGAffineTransform(translationX: g.lightAt.x * w, y: h - g.lightAt.y * h)))
        return glow.composited(over: linear.outputImage ?? CIImage.empty()).cropped(to: canvas)
    }

    static func color(hex: String) -> CIColor {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0x3E4A4F
        return CIColor(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255,
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) ?? CIColor(red: 0.24, green: 0.29, blue: 0.31)
    }
}
