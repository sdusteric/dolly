import AppKit
import DollyCore
import DollyRender
import DollyUI
import Foundation

/// The studio's background work for the editor: captions from the take's microphone, and picture
/// backdrops copied into the take folder. Owned by the EditorController.
@MainActor
@Observable
final class StudioTasks {
    private(set) var transcription: [UUID: TranscriptionStatus] = [:]
    @ObservationIgnored private let store: TakeStore
    @ObservationIgnored private let transcriber: any Transcribing
    @ObservationIgnored private let log: Log
    /// The editor for a take if it is the open one; captions for any other take are saved to disk.
    @ObservationIgnored var openEditor: (UUID) -> EditorModel? = { _ in nil }
    @ObservationIgnored var window: () -> NSWindow? = { nil }
    /// The picture changed under the same file name, so the preview must reload it.
    @ObservationIgnored var backdropChanged: () -> Void = {}

    static let replaceTitle = "Replace your edited captions?"
    static let replaceDetail = "Transcribe again writes new captions from your voice and drops the changes you made."

    init(store: TakeStore, log: Log, transcriber: any Transcribing = Transcriber()) {
        self.store = store
        self.log = log
        self.transcriber = transcriber
    }

    func status(_ id: UUID?) -> TranscriptionStatus { id.flatMap { transcription[$0] } ?? .idle }

    // MARK: Captions

    /// Transcribe again: asks first when the owner edited the captions.
    func transcribeAgain(_ editor: EditorModel, folder: URL) {
        guard editor.take.captions?.edited == true, let window = window() else { return transcribe(editor.take, folder: folder) }
        let alert = NSAlert()
        alert.messageText = Self.replaceTitle
        alert.informativeText = Self.replaceDetail
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            MainActor.assumeIsolated { self?.transcribe(editor.take, folder: folder) }
        }
    }

    /// Captions from `audio.m4a`, on this Mac. Nothing happens for a take without a microphone.
    func transcribe(_ take: Take, folder: URL) {
        guard let offset = take.microphoneOffset, transcription[take.id] != .working else { return }
        let id = take.id
        let audio = folder.appending(path: TakeStore.audioName)
        let locale = Locale.current
        transcription[id] = .working
        let transcriber = transcriber
        Task {
            do {
                let phrases = try await transcriber.transcribe(audio: audio, locale: locale)
                let latest = openEditor(id)?.take ?? (try? store.load(folder)) ?? take
                let track = CaptionTrack.transcribed(phrases, locale: locale.identifier, offset: offset, keeping: latest.captions)
                apply(track, to: id, folder: folder)
                transcription[id] = .idle
            } catch {
                log.warning("transcribing \(id.uuidString) failed: \(error.localizedDescription)")
                transcription[id] = .failed(error.localizedDescription)
            }
        }
    }

    private func apply(_ track: CaptionTrack, to id: UUID, folder: URL) {
        if let editor = openEditor(id) { return editor.setCaptions(track) }
        do {
            var take = try store.load(folder)
            take.captions = track
            try store.save(take)
        } catch {
            log.error("saving captions for \(id.uuidString) failed: \(error.localizedDescription)")
        }
    }

    // MARK: Backdrops

    /// Desktop takes the picture of the display the take was recorded on; Choose… asks for a file.
    func chooseBackdrop(_ pick: BackdropPick, editor: EditorModel, folder: URL) {
        switch pick {
        case .desktop:
            let rect = editor.take.recordingRect ?? .zero
            let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) } ?? NSScreen.main
            guard let screen, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return NSSound.beep() }
            importBackdrop(url, editor: editor, folder: folder)
        case .choose:
            guard let window = window() else { return }
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            panel.prompt = "Use Picture"
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                MainActor.assumeIsolated { self?.importBackdrop(url, editor: editor, folder: folder) }
            }
        }
    }

    private func importBackdrop(_ url: URL, editor: EditorModel, folder: URL) {
        do {
            let name = try store.importBackdrop(url, into: folder)
            var blur = 0.0
            if case .picture(_, let b) = editor.take.look.background { blur = b }
            editor.setBackdrop(.picture(file: name, blur: blur))
            backdropChanged()
        } catch {
            log.warning("backdrop from \(url.lastPathComponent) failed: \(error.localizedDescription)")
            NSSound.beep()
        }
    }
}
