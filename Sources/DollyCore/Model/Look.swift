import Foundation

/// How a take looks around the recording (spec 6.4 and 4.7). Belongs to the take; "Use for new
/// takes" copies it into the settings.
public struct Look: Codable, Hashable, Sendable {
    public enum Background: Codable, Hashable, Sendable {
        case color(hex: String)
    }

    /// The five flat backgrounds of the inspector, in order. The first is the default.
    public static let backgrounds = ["#3E4A4F", "#D9CFC0", "#1F2A44", "#F2F2F2", "#7A3B2E"]

    public var background: Background = .color(hex: Look.backgrounds[0])
    /// Points at a 1080 px short side; scaled with the output.
    public var padding: Double = 64
    public var corners: Double = 12
    public var shadow = true
    public var pointerScale: Double = 1.5
    public var smoothPointer = true
    public var clickRing = true
    public var hideWhenStill = false

    public init() {}
}
