import Foundation

public struct PlatformLimit: Sendable, Hashable {
    public var name: String
    public var maxSeconds: Double
}

/// Video length limits, checked 2026-10-26: X without Premium 2:20, Threads 5:00. They change, so
/// they live in one table and only ever warn (spec 6.3 and 7).
public enum PlatformLimits {
    public static let all = [PlatformLimit(name: "X", maxSeconds: 140), PlatformLimit(name: "Threads", maxSeconds: 300)]

    public static func lengthLine(_ seconds: Double) -> String {
        let fits = all.filter { seconds <= $0.maxSeconds + 1e-9 }
        let over = all.filter { seconds > $0.maxSeconds + 1e-9 }
        func fitText(_ l: PlatformLimit) -> String { "\(l.name) (\(TimeText.short(l.maxSeconds)) max)" }
        func overText(_ l: PlatformLimit) -> String { "\(l.name) by \(TimeText.short(seconds - l.maxSeconds))" }
        if over.isEmpty { return "Fits " + fits.map(fitText).joined(separator: " and ") }
        let tooLong = "Too long for " + over.map(overText).joined(separator: " and for ")
        return fits.isEmpty ? tooLong : tooLong + ". Fits " + fits.map(fitText).joined(separator: " and ")
    }
}
