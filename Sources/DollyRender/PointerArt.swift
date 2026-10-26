import CoreGraphics
import CoreImage
import DollyCore
import Foundation

/// The pointer Dolly draws in the clip (spec 4.7): black with a white outline and a soft shadow,
/// from vector paths on a 20 x 26 unit grid. `tip` is where the hot spot sits in units.
enum PointerArt {
    static let units = CGSize(width: 22, height: 28)

    static func path(_ shape: PointerShape) -> (path: CGPath, tip: CGPoint) {
        let p = CGMutablePath()
        switch shape {
        case .ibeam:
            p.addRect(CGRect(x: 9.2, y: 4, width: 1.6, height: 18))
            p.addRect(CGRect(x: 6, y: 3, width: 8, height: 1.8))
            p.addRect(CGRect(x: 6, y: 21.2, width: 8, height: 1.8))
            return (p, CGPoint(x: 10, y: 13))
        case .pointingHand:
            p.addRoundedRect(in: CGRect(x: 7, y: 2, width: 4, height: 12), cornerWidth: 2, cornerHeight: 2)
            p.addRoundedRect(in: CGRect(x: 4, y: 11, width: 13, height: 12), cornerWidth: 4, cornerHeight: 4)
            return (p, CGPoint(x: 9, y: 2))
        case .arrow, .other:
            p.move(to: CGPoint(x: 2, y: 2))
            for point in [(2, 21), (7, 16.5), (10.5, 24), (13.5, 22.6), (10.2, 15.4), (16.6, 15.4)] {
                p.addLine(to: CGPoint(x: point.0, y: point.1))
            }
            p.closeSubpath()
            return (p, CGPoint(x: 2, y: 2))
        }
    }

    /// The pointer as an image whose extent origin is 0,0, and the tip's offset in pixels from
    /// the image's top-left. `unit` is pixels per grid unit.
    static func image(_ shape: PointerShape, unit: Double) -> (image: CIImage, tip: CGPoint)? {
        let pad = 4.0
        let width = Int(((units.width + 2 * pad) * unit).rounded(.up))
        let height = Int(((units.height + 2 * pad) * unit).rounded(.up))
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let (path, tip) = path(shape)
        // Grid units are top-left; CGContext is bottom-left.
        ctx.translateBy(x: 0, y: Double(height))
        ctx.scaleBy(x: unit, y: -unit)
        ctx.translateBy(x: pad, y: pad)
        ctx.setShadow(offset: CGSize(width: 0, height: -0.6 * unit), blur: 2.5 * unit,
                      color: CGColor(gray: 0, alpha: 0.35))
        ctx.addPath(path)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.setLineWidth(3.2)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
        ctx.drawPath(using: .fillStroke)
        ctx.setShadow(offset: .zero, blur: 0)
        ctx.addPath(path)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fillPath()
        guard let cg = ctx.makeImage() else { return nil }
        return (CIImage(cgImage: cg), CGPoint(x: (tip.x + pad) * unit, y: (tip.y + pad) * unit))
    }
}
