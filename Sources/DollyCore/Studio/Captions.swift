import Foundation

public struct Caption: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var text: String

    public init(id: UUID = UUID(), start: Double, end: Double, text: String) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
    }
}

/// The take's captions (studio spec, Captions). Drawn into the video; `.srt` beside it when asked.
public struct CaptionTrack: Codable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable { case voice, typed }

    public static let sizeRange = 10.0...24.0

    public var source: Source
    public var locale: String
    public var position = CaptionPosition.bottom
    /// Points at a 1080 px short side.
    public var size = 15.0
    public var saveSRT = false
    /// Sorted by start, never overlapping.
    public var items: [Caption]
    /// The owner changed a caption since the last transcription, so Transcribe again asks first.
    public var edited = false

    public init(source: Source, locale: String, items: [Caption] = []) {
        self.source = source
        self.locale = locale
        self.items = items
    }

    public func caption(at t: Double) -> Caption? { items.first { $0.start <= t && t < $0.end } }
}

/// What a transcriber hears: a run of speech with the time of each word, in seconds of the audio
/// file; the caller shifts them into the take.
public struct Phrase: Hashable, Sendable {
    public struct Word: Hashable, Sendable {
        public var text: String
        public var start: Double
        public var end: Double
        public init(text: String, start: Double, end: Double) {
            self.text = text
            self.start = start
            self.end = end
        }
    }

    public var text: String
    public var start: Double
    public var end: Double
    /// Empty when the transcriber gave no word times; the splitter then spreads the phrase's time.
    public var words: [Word]

    public init(text: String, start: Double, end: Double, words: [Word]) {
        self.text = text
        self.start = start
        self.end = end
        self.words = words
    }
}

/// Turns recorded speech into phrases. `Transcriber` (DollyRender) is the real one.
public protocol Transcribing: Sendable {
    func transcribe(audio: URL, locale: Locale) async throws -> [Phrase]
}
