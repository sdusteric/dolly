import CoreGraphics
import Foundation

/// One zoom on the timeline (spec 5.1 and 8). Times are seconds of recording time; `start` is where
/// the move in begins and `end` is where the move out finishes. `aim` is in recording points.
public struct Zoom: Codable, Hashable, Identifiable, Sendable {
    public enum Mode: String, Codable, Sendable { case hold, follow }
    public enum Source: String, Codable, Sendable { case auto, manual }

    public var id: UUID
    public var start: Double
    public var end: Double
    public var aim: CGPoint
    public var depth: Double
    public var mode: Mode
    public var moveIn: Double
    public var moveOut: Double
    public var source: Source
    public var clickIDs: [Int]
    public var name: String

    public init(
        id: UUID = UUID(), start: Double, end: Double, aim: CGPoint, depth: Double, mode: Mode,
        moveIn: Double, moveOut: Double, source: Source, clickIDs: [Int], name: String
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.aim = aim
        self.depth = depth
        self.mode = mode
        self.moveIn = moveIn
        self.moveOut = moveOut
        self.source = source
        self.clickIDs = clickIDs
        self.name = name
    }

    public var length: Double { end - start }
}
