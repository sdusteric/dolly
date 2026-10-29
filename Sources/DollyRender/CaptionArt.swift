import CoreGraphics
import CoreImage
import CoreText
import DollyCore
import Foundation
import Synchronization

/// One caption as an image (studio spec, Style): Avenir Next Demi Bold, white, centered, at most
/// two lines on a near-black pill at 74 %. Cached, since the same caption draws for many frames.
public enum CaptionArt {
    struct Key: Hashable {
        let text: String
        let size: Double
        let k: Double
        let maxWidth: Double
    }

    static let cache = Mutex<[Key: CIImage]>([:])
    static let fontName = "AvenirNext-DemiBold"

    public static func image(text: String, sizePoints: Double, k: Double, maxWidth: Double) -> CIImage? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, maxWidth > 0 else { return nil }
        let key = Key(text: text, size: sizePoints, k: k, maxWidth: maxWidth)
        if let hit = cache.withLock({ $0[key] }) { return hit }
        guard let image = draw(text, sizePoints: sizePoints, k: k, maxWidth: maxWidth) else { return nil }
        cache.withLock { stored in
            if stored.count > 64 { stored.removeAll() }
            stored[key] = image
        }
        return image
    }

    static func draw(_ text: String, sizePoints: Double, k: Double, maxWidth: Double) -> CIImage? {
        var wrapped = CaptionSplitter.lines(text, maxLine: 42)
        if wrapped.count > 2 { wrapped = [wrapped[0], wrapped[1...].joined(separator: " ")] }
        let padX = 14 * k, padY = 6 * k
        var size = sizePoints * k
        var lines: [CTLine] = []
        var widths: [Double] = []
        // A typed caption too wide for the canvas draws smaller instead of running off it.
        for _ in 0..<2 {
            let font = CTFontCreateWithName(fontName as CFString, size, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
            ]
            lines = wrapped.map { CTLineCreateWithAttributedString(NSAttributedString(string: $0, attributes: attributes)) }
            widths = lines.map { CTLineGetTypographicBounds($0, nil, nil, nil) }
            let widest = widths.max() ?? 0
            guard widest + 2 * padX > maxWidth, widest > 0 else { break }
            size *= (maxWidth - 2 * padX) / widest
        }
        let font = CTFontCreateWithName(fontName as CFString, size, nil)
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
        let lineHeight = (size * 1.3).rounded()
        let width = Int(((widths.max() ?? 0) + 2 * padX).rounded(.up))
        let height = Int((Double(lines.count) * lineHeight + 2 * padY).rounded(.up))
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let box = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: 8 * k, cornerHeight: 8 * k, transform: nil))
        ctx.setFillColor(CGColor(srgbRed: 12 / 255, green: 12 / 255, blue: 12 / 255, alpha: 0.74))
        ctx.fillPath()
        for (i, line) in lines.enumerated() {
            let top = padY + Double(i) * lineHeight + (lineHeight - ascent - descent) / 2
            ctx.textPosition = CGPoint(x: (Double(width) - widths[i]) / 2, y: Double(height) - top - ascent)
            CTLineDraw(line, ctx)
        }
        return ctx.makeImage().map { CIImage(cgImage: $0) }
    }
}
