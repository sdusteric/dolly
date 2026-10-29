import CoreGraphics
import Foundation

/// Export shapes (spec 7, studio spec item 1). Original keeps the recording's own aspect.
public enum ShapePreset: String, Codable, CaseIterable, Sendable {
    case original, wide16x9, square1x1, portrait4x5, tall9x16

    /// Output pixels. Original scales the recording so its long side is 1920 px, each side rounded
    /// to the nearest even number for H.264.
    public func pixelSize(recording: CGSize) -> PixelSize {
        switch self {
        case .original:
            let w = max(recording.width, 1), h = max(recording.height, 1)
            let s = 1920 / max(w, h)
            func even(_ v: Double) -> Int { max(2, Int((v / 2).rounded()) * 2) }
            return PixelSize(width: even(w * s), height: even(h * s))
        case .wide16x9: return PixelSize(width: 1920, height: 1080)
        case .square1x1: return PixelSize(width: 1080, height: 1080)
        case .portrait4x5: return PixelSize(width: 1080, height: 1350)
        case .tall9x16: return PixelSize(width: 1080, height: 1920)
        }
    }

    public var label: String {
        switch self {
        case .original: "Original"
        case .wide16x9: "16:9"
        case .square1x1: "1:1"
        case .portrait4x5: "4:5"
        case .tall9x16: "9:16"
        }
    }

    public var fileSuffix: String { self == .original ? "original" : label.replacingOccurrences(of: ":", with: "x") }
}
