import Foundation

/// SubRip text for the `.srt` beside an export, with times from the trim start.
public enum SRT {
    public static func text(_ items: [Caption], trimStart: Double) -> String {
        items.filter { $0.end > trimStart }.enumerated().map { i, c in
            "\(i + 1)\n\(stamp(c.start - trimStart)) --> \(stamp(c.end - trimStart))\n\(c.text)\n"
        }.joined(separator: "\n")
    }

    static func stamp(_ seconds: Double) -> String {
        let ms = Int((max(seconds, 0) * 1000).rounded())
        let h = ms / 3_600_000, m = ms / 60_000 % 60, s = ms / 1000 % 60
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms % 1000)
    }
}
