import Foundation

/// A stretch of the take, in take seconds, that is cut out of the clip or played faster.
public struct SpeedRegion: Codable, Hashable, Identifiable, Sendable {
    public enum Speed: Codable, Hashable, Sendable {
        case cut
        case fast(Double)

        /// The speeds the editor offers, slowest last.
        public static let choices: [Speed] = [.cut, .fast(2), .fast(4), .fast(8)]

        public var label: String {
            switch self {
            case .cut: "Cut"
            case .fast(let rate): "\(Int(rate))×"
            }
        }
    }

    public var id: UUID
    public var start: Double
    public var end: Double
    public var speed: Speed

    public init(id: UUID = UUID(), start: Double, end: Double, speed: Speed) {
        self.id = id
        self.start = start
        self.end = end
        self.speed = speed
    }

    public var length: Double { end - start }
}

extension Take {
    /// Cuts and speed-ups, sorted; stored as `speeds` and left out of take.json when empty.
    public var speedRegions: [SpeedRegion] {
        get { speeds ?? [] }
        set { speeds = newValue.isEmpty ? nil : newValue.sorted { $0.start < $1.start } }
    }

    public var timeMap: TimeMap { TimeMap(trim: trim, regions: speedRegions) }

    /// The clip's length after the trim, cuts and speed-ups.
    public var outputDuration: Double { timeMap.duration }
}
