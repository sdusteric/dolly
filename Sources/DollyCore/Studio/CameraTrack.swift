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

    public init(startOffset: Double) {
        self.startOffset = startOffset
    }

    public func isVisible(at t: Double) -> Bool { !hidden.contains { $0.contains(t) } }
}
