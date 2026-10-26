// swift make-icon.swift out.png : 1024x1024 app icon (spec 10.7). A dark stage square with two
// pink spike-tape L corners framing the middle, the mark Dolly puts where the camera lands.
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let size = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: rep) else {
    FileHandle.standardError.write(Data("could not make a bitmap\n".utf8))
    exit(1)
}
NSGraphicsContext.current = context
func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
// The macOS icon grid: an 824 pt rounded square centered in 1024.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
color(0x1E2124).setFill()
NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185).fill()
// A soft recording frame in the middle, then the tape corners around it.
color(0x3E4A4F).setFill()
NSBezierPath(roundedRect: NSRect(x: 292, y: 352, width: 440, height: 320), xRadius: 28, yRadius: 28).fill()
let tape = color(0xFF4F9A)
tape.setFill()
let t: CGFloat = 54, leg: CGFloat = 200
// top left
NSBezierPath(rect: NSRect(x: 232, y: 732 - t, width: leg, height: t)).fill()
NSBezierPath(rect: NSRect(x: 232, y: 732 - leg, width: t, height: leg)).fill()
// bottom right
NSBezierPath(rect: NSRect(x: 792 - leg, y: 292, width: leg, height: t)).fill()
NSBezierPath(rect: NSRect(x: 792 - t, y: 292, width: t, height: leg)).fill()
NSGraphicsContext.current = nil
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
do { try png.write(to: URL(fileURLWithPath: out)) } catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
