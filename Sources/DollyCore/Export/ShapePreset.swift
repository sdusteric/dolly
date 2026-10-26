import Foundation

/// Export shapes (spec 7). M1 exports only 16:9; the others exist so the layout math is general.
public enum ShapePreset: String, Codable, CaseIterable, Sendable {
    case wide16x9, square1x1, portrait4x5, tall9x16

    public var pixelSize: PixelSize {
        switch self {
        case .wide16x9: PixelSize(width: 1920, height: 1080)
        case .square1x1: PixelSize(width: 1080, height: 1080)
        case .portrait4x5: PixelSize(width: 1080, height: 1350)
        case .tall9x16: PixelSize(width: 1080, height: 1920)
        }
    }

    public var label: String {
        switch self {
        case .wide16x9: "16:9"
        case .square1x1: "1:1"
        case .portrait4x5: "4:5"
        case .tall9x16: "9:16"
        }
    }

    public var fileSuffix: String { label.replacingOccurrences(of: ":", with: "x") }
}
