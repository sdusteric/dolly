import CoreGraphics
import CoreImage
import Foundation
@testable import DollyCore
@testable import DollyRender

let testContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

/// RGBA8 of one pixel, (x, y) from the top-left of `image`'s extent.
func pixel(_ image: CIImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    var px = [UInt8](repeating: 0, count: 4)
    let e = image.extent
    testContext.render(image, toBitmap: &px, rowBytes: 4,
                       bounds: CGRect(x: e.minX + Double(x), y: e.maxY - Double(y) - 1, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    return (Int(px[0]), Int(px[1]), Int(px[2]), Int(px[3]))
}

func near(_ p: (r: Int, g: Int, b: Int, a: Int), _ hex: UInt32, tol: Int = 3) -> Bool {
    abs(p.r - Int(hex >> 16 & 0xFF)) <= tol && abs(p.g - Int(hex >> 8 & 0xFF)) <= tol && abs(p.b - Int(hex & 0xFF)) <= tol
}

/// A red recording, `size` points at 1x, with a 40 x 40 pt blue square whose top-left is `square`.
func redRecording(size: CGSize, square: CGPoint) -> CIImage {
    let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(origin: .zero, size: size))
    let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1))
        .cropped(to: CGRect(x: square.x, y: size.height - square.y - 40, width: 40, height: 40))
    return blue.composited(over: red)
}
