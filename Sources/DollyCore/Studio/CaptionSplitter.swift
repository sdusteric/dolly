import Foundation

/// Phrases into captions of at most two lines of about 42 characters, split at sentence ends and at
/// pauses (studio spec, Splitting).
public enum CaptionSplitter {
    public static func captions(from phrases: [Phrase], maxLine: Int = 42, maxLines: Int = 2, pause: Double = 0.4) -> [Caption] {
        var out: [Caption] = []
        for phrase in phrases {
            var current: [Phrase.Word] = []
            func flush() {
                guard let first = current.first, let last = current.last else { return }
                out.append(Caption(start: first.start, end: last.end, text: current.map(\.text).joined(separator: " ")))
                current = []
            }
            for word in words(of: phrase) {
                if let last = current.last {
                    let sentenceEnd = last.text.last.map { ".!?".contains($0) } ?? false
                    let tooLong = lines((current + [word]).map(\.text).joined(separator: " "), maxLine: maxLine).count > maxLines
                    if sentenceEnd || word.start - last.end > pause || tooLong { flush() }
                }
                current.append(word)
            }
            flush()
        }
        return separated(out.sorted { $0.start < $1.start })
    }

    /// Greedy wrap at spaces. A word longer than a line gets a line of its own.
    public static func lines(_ text: String, maxLine: Int) -> [String] {
        var lines: [String] = []
        var line = ""
        for word in text.split(separator: " ") {
            if line.isEmpty {
                line = String(word)
            } else if line.count + 1 + word.count <= maxLine {
                line += " " + word
            } else {
                lines.append(line)
                line = String(word)
            }
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }

    /// The phrase's words, or its text spread evenly over its time when it has no word times.
    static func words(of phrase: Phrase) -> [Phrase.Word] {
        let given = phrase.words.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        if !given.isEmpty { return given }
        let texts = phrase.text.split(separator: " ").map(String.init)
        guard !texts.isEmpty else { return [] }
        let step = max(phrase.end - phrase.start, 0) / Double(texts.count)
        return texts.enumerated().map { i, text in
            Phrase.Word(text: text, start: phrase.start + Double(i) * step, end: phrase.start + Double(i + 1) * step)
        }
    }

    /// Ends never run past the next start, and every caption lasts at least a moment.
    static func separated(_ items: [Caption]) -> [Caption] {
        var out = items
        for i in out.indices {
            if i > 0, out[i].start <= out[i - 1].start { out[i].start = out[i - 1].start + 0.01 }
            if i + 1 < out.count { out[i].end = min(out[i].end, out[i + 1].start) }
            out[i].end = max(out[i].end, out[i].start + 0.01)
        }
        return out
    }
}
