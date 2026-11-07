import Foundation

/// Take time to clip time (spec 6.3.1): the trim, less the cuts, with speed-ups shortened. The
/// player, the compositor, the exporter and the .srt all go through it, so they agree.
public struct TimeMap: Hashable, Sendable {
    /// A stretch of the take that is in the clip, played at `rate`.
    public struct Piece: Hashable, Sendable {
        public let start: Double
        public let end: Double
        public let rate: Double
        public let outputStart: Double
        public var outputEnd: Double { outputStart + (end - start) / rate }
    }

    /// Shorter regions and pieces are dropped, so a stray click never makes a sliver.
    public static let shortest = 0.05

    public let trim: ClosedRange<Double>
    public let pieces: [Piece]

    public init(trim: ClosedRange<Double>, regions: [SpeedRegion]) {
        self.trim = trim
        // Clip to the trim, sort, and let the earlier region win where two overlap.
        var kept: [(start: Double, end: Double, speed: SpeedRegion.Speed)] = []
        var from = trim.lowerBound
        for r in regions.sorted(by: { $0.start < $1.start }) {
            let start = max(r.start, from, trim.lowerBound), end = min(r.end, trim.upperBound)
            guard end - start >= Self.shortest else { continue }
            kept.append((start, end, r.speed))
            from = end
        }
        var pieces: [Piece] = []
        var output = 0.0, cursor = trim.lowerBound
        func add(_ start: Double, _ end: Double, _ rate: Double) {
            guard end - start >= Self.shortest else { return }
            let piece = Piece(start: start, end: end, rate: rate, outputStart: output)
            pieces.append(piece)
            output = piece.outputEnd
        }
        for r in kept {
            add(cursor, r.start, 1)
            if case .fast(let rate) = r.speed { add(r.start, r.end, max(rate, 1)) }
            cursor = r.end
        }
        add(cursor, trim.upperBound, 1)
        // A take cut down to nothing plays its whole trim instead.
        if output < Self.shortest {
            pieces = [Piece(start: trim.lowerBound, end: trim.upperBound, rate: 1, outputStart: 0)]
        }
        self.pieces = pieces
    }

    public var duration: Double { pieces.last?.outputEnd ?? 0 }

    /// Where take time `t` plays in the clip. A time inside a cut plays where the cut is.
    public func output(at t: Double) -> Double {
        for piece in pieces {
            if t < piece.start { return piece.outputStart }
            if t <= piece.end { return piece.outputStart + (t - piece.start) / piece.rate }
        }
        return duration
    }

    /// The take time shown at clip time `o`; at a cut, the frame after it.
    public func source(at o: Double) -> Double {
        for piece in pieces where o < piece.outputEnd {
            return piece.start + max(o - piece.outputStart, 0) * piece.rate
        }
        return pieces.last?.end ?? trim.upperBound
    }

    /// Inside the trim but cut out of the clip.
    public func isCut(_ t: Double) -> Bool {
        trim.contains(t) && !pieces.contains { t >= $0.start && t <= $0.end }
    }
}
