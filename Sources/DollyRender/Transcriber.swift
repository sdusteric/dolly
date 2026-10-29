import AVFoundation
import DollyCore
import Foundation
import Speech

/// Captions from the owner's voice, on this Mac (studio spec, Captions). macOS may download the
/// language model once through `AssetInventory`; Dolly makes no network request itself. Exercised
/// only by the owner's S3 check, never by tests.
public struct Transcriber: Transcribing {
    public init() {}

    public func transcribe(audio: URL, locale: Locale) async throws -> [Phrase] {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriberError.language(locale.identifier)
        }
        let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: [], reportingOptions: [],
                                            attributeOptions: [.audioTimeRange])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: audio)
        async let collected: [Phrase] = transcriber.results.reduce(into: []) { phrases, result in
            phrases.append(Self.phrase(from: result))
        }
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        return try await collected.filter { !$0.text.isEmpty }
    }

    static func phrase(from result: SpeechTranscriber.Result) -> Phrase {
        var words: [Phrase.Word] = []
        for run in result.text.runs {
            let text = String(result.text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let range = run.audioTimeRange else { continue }
            words.append(Phrase.Word(text: text, start: range.start.seconds, end: range.end.seconds))
        }
        return Phrase(text: String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines),
                      start: result.range.start.seconds, end: result.range.end.seconds, words: words)
    }
}

public enum TranscriberError: Error, LocalizedError {
    case language(String)

    public var errorDescription: String? {
        switch self {
        case .language(let id): "This Mac can't transcribe \(Locale.current.localizedString(forIdentifier: id) ?? id)."
        }
    }
}
