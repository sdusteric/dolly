import Foundation

/// SubRip text for the `.srt` beside an export, with times from the trim start.
public enum SRT {
    public static func text(_ items: [Caption], trimStart: Double) -> String {
        items.filter { $0.end > trimStart }.enumerated().map { i, c in
            "\(i + 1)\n\(stamp(c.start - trimStart)) --> \(stamp(c.end - trimStart))\n\(c.text)\n"
        }.joined(separator: "\n")
    }

    /// A take's captions as its export's .srt, or "" when none play in the clip.
    public static func text(for take: Take) -> String {
        text((take.captions?.items ?? []).filter { !$0.text.isEmpty }, map: take.timeMap)
    }

    /// Times in the clip: through the trim, cuts and speed-ups. A caption wholly cut is left out.
    public static func text(_ items: [Caption], map: TimeMap) -> String {
        items.compactMap { c -> (Double, Double, String)? in
            let start = map.output(at: c.start), end = map.output(at: c.end)
            return end - start >= TimeMap.shortest ? (start, end, c.text) : nil
        }.enumerated().map { i, c in
            "\(i + 1)\n\(stamp(c.0)) --> \(stamp(c.1))\n\(c.2)\n"
        }.joined(separator: "\n")
    }

    static func stamp(_ seconds: Double) -> String {
        let ms = Int((max(seconds, 0) * 1000).rounded())
        let h = ms / 3_600_000, m = ms / 60_000 % 60, s = ms / 1000 % 60
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms % 1000)
    }
}
