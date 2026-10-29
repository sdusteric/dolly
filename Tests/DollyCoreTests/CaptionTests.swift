import Foundation
import Testing
@testable import DollyCore

@Suite struct CaptionTests {
    /// Words with times, one after another, `gap` seconds apart (0 means touching).
    func phrase(_ text: String, from start: Double, perWord: Double = 0.3, gaps: [Int: Double] = [:]) -> Phrase {
        var t = start
        var words: [Phrase.Word] = []
        for (i, w) in text.split(separator: " ").enumerated() {
            t += gaps[i] ?? 0
            words.append(Phrase.Word(text: String(w), start: t, end: t + perWord))
            t += perWord
        }
        return Phrase(text: text, start: start, end: t, words: words)
    }

    func fits(_ c: Caption) -> Bool {
        let lines = CaptionSplitter.lines(c.text, maxLine: 42)
        return lines.count <= 2 && lines.allSatisfy { $0.count <= 42 || !$0.contains(" ") }
    }

    @Test func splitsAtSentenceEndsAndPauses() {
        let p = phrase("This is Shelf. Haul shows downloads and Run check up", from: 1, gaps: [6: 0.6])
        let captions = CaptionSplitter.captions(from: [p])
        #expect(captions.map(\.text) == ["This is Shelf.", "Haul shows downloads", "and Run check up"])
        #expect(captions[0].start == 1 && approx(captions[0].end, 1.9))
        #expect(approx(captions[2].start, 1 + 6 * 0.3 + 0.6))
    }

    @Test func longPhrasesSplitWithinLimits() {
        let long = String(repeating: "word ", count: 28).trimmingCharacters(in: .whitespaces)   // 139 characters
        let giant = String(repeating: "x", count: 50)
        let phrases = [phrase(long, from: 0), phrase("before \(giant) after", from: 20)]
        let captions = CaptionSplitter.captions(from: phrases)
        #expect(captions.count >= 3)
        #expect(captions.allSatisfy { !$0.text.isEmpty && fits($0) && $0.end > $0.start })
        #expect(captions.map(\.text).joined(separator: " ").split(separator: " ").count == 28 + 3)
        for (a, b) in zip(captions, captions.dropFirst()) {
            #expect(a.start < b.start && a.end <= b.start)
        }
        #expect(captions.contains { $0.text.contains(giant) })
    }

    @Test func phraseWithoutWordsSpreadsItsTime() {
        let captions = CaptionSplitter.captions(from: [Phrase(text: "Hello there.", start: 2, end: 3, words: [])])
        #expect(captions.count == 1 && captions[0].start == 2 && captions[0].end == 3)
    }

    @Test func srtFormatsRelativeToTrim() {
        let items = [Caption(start: 13.4, end: 16.6, text: "Each tile has its own quick actions."),
                     Caption(start: 1.0, end: 1.5, text: "Cut by the trim."),
                     Caption(start: 3725.25, end: 3726, text: "An hour in.")]
        #expect(SRT.text(items, trimStart: 2.0) == """
        1
        00:00:11,400 --> 00:00:14,600
        Each tile has its own quick actions.

        2
        01:02:03,250 --> 01:02:04,000
        An hour in.

        """)
    }

    @Test func captionAtTime() {
        let track = SyntheticTake.shelfCaptions()
        #expect(track.items.count == 10)
        #expect(track.caption(at: 12.4)?.text == "Each tile has its own quick actions.")
        #expect(track.caption(at: 11.2) == nil)
    }

    @Test func m1TakeHasNoCaptions() throws {
        let take = try JSONDecoder().decode(Take.self, from: Data(m1TakeJSON().utf8))
        #expect(take.captions == nil)
    }

    @Test func fakeTranscriberReturnsItsPhrases() async throws {
        let p = phrase("Hi there", from: 0)
        let out = try await FakeTranscriber(phrases: [p]).transcribe(audio: URL(filePath: "/nope.m4a"), locale: Locale(identifier: "en_US"))
        #expect(out == [p])
    }
}
