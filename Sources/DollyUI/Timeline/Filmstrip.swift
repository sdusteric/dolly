import Observation
import SwiftUI

/// The video lane's frames: one still from the middle of each even slice of the take, filled in the
/// background after the take opens. Until then the lane shows the poster.
@Observable
public final class Filmstrip {
    public var frames: [Image]

    public init(frames: [Image] = []) {
        self.frames = frames
    }

    /// How many stills a take gets: enough for a wide timeline without decoding the whole movie.
    public nonisolated static let count = 32

    public nonisolated static func times(duration: Double, count: Int) -> [Double] {
        guard duration > 0, count > 0 else { return [] }
        let slice = duration / Double(count)
        return (0..<count).map { (Double($0) + 0.5) * slice }
    }

    /// The still for time `t`: the slice `t` falls in, clamped to the ends.
    public nonisolated static func index(at t: Double, duration: Double, count: Int) -> Int {
        guard duration > 0, count > 0 else { return 0 }
        return min(max(Int(t / duration * Double(count)), 0), count - 1)
    }
}
