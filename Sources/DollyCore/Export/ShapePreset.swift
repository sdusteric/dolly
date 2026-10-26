import Foundation

/// Export shapes (spec 7). Sizes and labels are added with the shape layout.
public enum ShapePreset: String, Codable, CaseIterable, Sendable {
    case wide16x9, square1x1, portrait4x5, tall9x16
}
