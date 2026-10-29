import Foundation

/// Returns fixed phrases, or throws, without touching Speech.
public struct FakeTranscriber: Transcribing {
    public var phrases: [Phrase]
    public var failure: String?

    public init(phrases: [Phrase], failure: String? = nil) {
        self.phrases = phrases
        self.failure = failure
    }

    public func transcribe(audio: URL, locale: Locale) async throws -> [Phrase] {
        if let failure { throw FakeTranscriberError(message: failure) }
        return phrases
    }
}

public struct FakeTranscriberError: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}
