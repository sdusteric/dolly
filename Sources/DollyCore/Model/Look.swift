import Foundation

/// How a take looks around the recording (spec 6.4 and 4.7, studio spec item 3). Belongs to the
/// take; "Use for new takes" copies it into the settings.
public struct Look: Codable, Hashable, Sendable {
    public enum Background: Codable, Hashable, Sendable {
        case color(hex: String)
        /// One of `Backdrop.gradients`.
        case gradient(id: String)
        /// A picture copied into the take folder; `blur` in points at a 1080 px short side.
        case picture(file: String, blur: Double)
    }

    /// The flat backgrounds of the inspector, in order. The first is the default.
    public static let flatColors = ["#3E4A4F", "#D9CFC0", "#1F2A44", "#F2F2F2", "#7A3B2E", "#151413"]
    public static let defaultBackground = Background.color(hex: flatColors[0])

    public var background: Background = Look.defaultBackground
    /// Points at a 1080 px short side; scaled with the output.
    public var padding: Double = 64
    public var corners: Double = 12
    /// 0 to 1. M1 stored a Bool: `true` reads as 0.6, which draws the same shadow M1 did.
    public var shadow: Double = 0.6
    public var pointerScale: Double = 1.5
    public var smoothPointer = true
    public var clickRing = true
    public var hideWhenStill = false

    public init() {}

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Look()
        background = try c.decodeIfPresent(Background.self, forKey: .background) ?? d.background
        padding = try c.decodeIfPresent(Double.self, forKey: .padding) ?? d.padding
        corners = try c.decodeIfPresent(Double.self, forKey: .corners) ?? d.corners
        if let old = try? c.decodeIfPresent(Bool.self, forKey: .shadow) {
            shadow = old ? 0.6 : 0
        } else {
            shadow = try c.decodeIfPresent(Double.self, forKey: .shadow) ?? d.shadow
        }
        pointerScale = try c.decodeIfPresent(Double.self, forKey: .pointerScale) ?? d.pointerScale
        smoothPointer = try c.decodeIfPresent(Bool.self, forKey: .smoothPointer) ?? d.smoothPointer
        clickRing = try c.decodeIfPresent(Bool.self, forKey: .clickRing) ?? d.clickRing
        hideWhenStill = try c.decodeIfPresent(Bool.self, forKey: .hideWhenStill) ?? d.hideWhenStill
    }

    /// The look as it can be drawn from `folder`: a picture that is gone, or a gradient Dolly no
    /// longer has, becomes the default flat color.
    public func resolved(in folder: URL) -> Look {
        var look = self
        switch background {
        case .color:
            break
        case .gradient(let id):
            if Backdrop.gradient(id) == nil { look.background = Self.defaultBackground }
        case .picture(let file, _):
            if !FileManager.default.fileExists(atPath: folder.appending(path: file).path(percentEncoded: false)) {
                look.background = Self.defaultBackground
            }
        }
        return look
    }
}
