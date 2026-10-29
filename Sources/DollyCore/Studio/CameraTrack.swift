import CoreGraphics
import Foundation

/// The webcam recorded beside the screen (studio spec, Camera). `camera.mov` in the take folder.
public struct CameraTrack: Codable, Hashable, Sendable {
    public enum Shape: String, Codable, Sendable, CaseIterable { case circle, rounded }
    public enum Corner: String, Codable, Sendable, CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }

    public static let sizeRange = 0.10...0.40

    public var file = "camera.mov"
    /// Camera time 0 is this many seconds into the take.
    public var startOffset: Double
    /// Take times where the camera is hidden, sorted and not overlapping.
    public var hidden: [ClosedRange<Double>] = []
    public var shape = Shape.circle
    /// Fraction of the output's short side.
    public var size = 0.22
    public var corner = Corner.bottomLeft
    /// The bubble's center in unit canvas coordinates, set by dragging; wins over `corner`.
    public var point: CGPoint?
    public var border = true
    public var shrinkDuringZooms = true
    public var mirror = true
    /// The Camera tab's Show camera switch.
    public var shown = true

    public init(startOffset: Double) {
        self.startOffset = startOffset
    }

    /// Every key but `startOffset` may be missing, so takes keep opening as fields are added.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CameraTrack(startOffset: 0)
        startOffset = try c.decode(Double.self, forKey: .startOffset)
        file = try c.decodeIfPresent(String.self, forKey: .file) ?? d.file
        hidden = try c.decodeIfPresent([ClosedRange<Double>].self, forKey: .hidden) ?? d.hidden
        shape = try c.decodeIfPresent(Shape.self, forKey: .shape) ?? d.shape
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? d.size
        corner = try c.decodeIfPresent(Corner.self, forKey: .corner) ?? d.corner
        point = try c.decodeIfPresent(CGPoint.self, forKey: .point)
        border = try c.decodeIfPresent(Bool.self, forKey: .border) ?? d.border
        shrinkDuringZooms = try c.decodeIfPresent(Bool.self, forKey: .shrinkDuringZooms) ?? d.shrinkDuringZooms
        mirror = try c.decodeIfPresent(Bool.self, forKey: .mirror) ?? d.mirror
        shown = try c.decodeIfPresent(Bool.self, forKey: .shown) ?? d.shown
    }

    public func isVisible(at t: Double) -> Bool { shown && !hidden.contains { $0.contains(t) } }
}
