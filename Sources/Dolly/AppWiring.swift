import AppKit
import AVFoundation
import DollyCore
import DollyRender
import DollySystem
import DollyUI
import Observation
import SwiftUI

/// The editor window and everything it shows (spec 6): takes from the store, the preview player,
/// the Aim mode frame, saving edits, the export sheet and the Shelf status. Owned by the app
/// delegate; never created in shot mode or tests.
@MainActor
final class EditorController: NSObject, NSWindowDelegate {
    let screen: EditorScreenModel
    var onRecord: () -> Void = {}

    let paths: DollyPaths
    let store: TakeStore
    private let settingsStore: SettingsStore
    let log: Log
    private(set) var settings: DollyCore.Settings
    let preview = PreviewPlayer()
    private let studio: StudioTasks
    private(set) var window: NSWindow?
    private var aside = EditorStepAside()
    private let session: TakeSession
    private let filmstrip = Filmstrip()
    private var filmstripTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var reloadNumber = 0
    var shelfNumber = 0
    weak var exportModel: ExportSheetModel?
    /// A failed save alerts once; the next good save clears it.
    private var saveFailureShown = false

    init(paths: DollyPaths, settings: DollyCore.Settings, log: Log) {
        self.paths = paths
        self.settings = settings
        self.log = log
        store = TakeStore(paths: paths)
        session = TakeSession(store: store)
        settingsStore = SettingsStore(paths: paths)
        studio = StudioTasks(store: store, log: log)
        screen = EditorScreenModel(entries: [], totalBytes: 0, editor: nil, recordShortcut: settings.hotkey.displayString)
        super.init()
        studio.openEditor = { [weak self] id in self?.screen.editor.flatMap { $0.take.id == id ? $0 : nil } }
        studio.window = { [weak self] in self?.window }
        studio.backdropChanged = { [weak self] in self?.preview.takeChanged() }
        screen.onRecord = { [weak self] in self?.onRecord() }
        screen.onExport = { [weak self] in self?.showExport() }
        screen.onSelect = { [weak self] entry in self?.open(entry) }
        screen.onRename = { [weak self] entry, name in self?.rename(entry, to: name) }
        screen.onReveal = { entry in NSWorkspace.shared.activateFileViewerSelecting([Self.revealURL(entry)]) }
        screen.onTrash = { [weak self] entry in self?.trash(entry) }
        refreshTakes()
        Exporter.sweepScratch(in: exportsFolder)
    }

    var editor: EditorModel? { screen.editor }
    var folder: URL? { session.folder }

    // MARK: Window

    func showWindow() {
        let window = window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1280, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Dolly"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = CGSize(width: 1100, height: 720)
        window.isReleasedWhenClosed = false
        window.delegate = self
        let preview = preview, studio = studio
        let root = EditorView(model: screen) { [weak self] editor in
            var actions = StudioActions()
            actions.useForNewTakes = { look in self?.useForNewTakes(look) }
            actions.chooseBackdrop = { pick in
                if let folder = self?.folder { studio.chooseBackdrop(pick, editor: editor, folder: folder) }
            }
            actions.aimHintSeen = self?.settings.aimHintSeen ?? false
            actions.aimed = { self?.markAimHintSeen() }
            actions.transcribe = {
                if let folder = self?.folder { studio.transcribeAgain(editor, folder: folder) }
            }
            return AnyView(LiveWorkspace(editor: editor, preview: preview, studio: studio, filmstrip: self?.filmstrip, actions: actions))
        }
        window.contentView = NSHostingView(rootView: root.focusEffectDisabled())
        window.center()
        window.setFrameAutosaveName("DollyEditor")
        return window
    }

    /// The Record bar opened: the editor leaves the screen so the owner can see what to record.
    func stepAside() {
        guard let window, aside.hide(visible: window.isVisible, active: NSApp.isActive) else { return }
        preview.pause()
        window.orderOut(nil)
    }

    /// A recording started; the take card brings the editor back when it ends.
    func recordingStarted() { aside.started() }

    /// The bar closed with nothing recorded: the editor returns where it was.
    func recordingCancelled() {
        guard let window, let restore = aside.cancelled() else { return }
        switch restore {
        case .front: window.makeKeyAndOrderFront(nil)
        case .behind: window.orderBack(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        preview.pause()
        saveNow()
    }

    // MARK: Takes

    /// The take being recorded has no take.json yet; it is left out until it is saved.
    var recordingFolder: () -> URL? = { nil }

    /// Reads every take.json and walks the takes folder off the main actor; the newest call wins.
    /// The open take shows its edits as they are in memory, which may be newer than its file.
    func reloadTakes() async {
        reloadNumber += 1
        let number = reloadNumber
        let store = store
        let (entries, bytes) = await Task.detached { (store.list(), store.totalBytes()) }.value
        guard number == reloadNumber else { return }
        let recording = recordingFolder()?.standardizedFileURL
        var shown = entries.filter { $0.folder.standardizedFileURL != recording }
        if let editor = screen.editor, let folder, let patched = TakesSidebarModel.replacing(editor.take, at: folder, in: shown) {
            shown = patched
        }
        screen.entries = shown
        screen.totalBytes = bytes
        for case .ok(let take, let folder) in screen.entries where screen.posters[take.id] == nil {
            if let image = NSImage(contentsOf: folder.appending(path: TakeStore.posterName)) {
                screen.posters[take.id] = Image(nsImage: image)
            }
        }
    }

    func refreshTakes() {
        Task { await reloadTakes() }
    }

    /// After a save only the open take changed, so its sidebar entry is swapped in place.
    private func refreshOpenEntry() {
        guard let editor = screen.editor, let folder else { return }
        guard let patched = TakesSidebarModel.replacing(editor.take, at: folder, in: screen.entries) else { return refreshTakes() }
        if patched != screen.entries { screen.entries = patched }
    }

    func open(_ entry: TakeEntry) {
        switch entry {
        case .ok(_, let folder): open(folder: folder)
        case .broken(let folder, _): NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
    }

    func openLatest() {
        Task {
            await reloadTakes()
            if let first = screen.entries.first(where: { if case .ok = $0 { true } else { false } }) { open(first) }
            showWindow()
        }
    }

    /// The open take renames through its editor, so Undo can put the name back.
    private func rename(_ entry: TakeEntry, to name: String) {
        if isOpen(entry.folder), let editor = screen.editor {
            editor.renameTake(name)
            saveNow()
        } else {
            // One take.json is read back here, so the row shows the new name without a full reload.
            do {
                try store.rename(entry.folder, to: name)
                let take = try store.load(entry.folder)
                if let patched = TakesSidebarModel.replacing(take, at: entry.folder, in: screen.entries) { screen.entries = patched }
            } catch {
                log.error("renaming take \(entry.folder.lastPathComponent) failed: \(error.localizedDescription)")
                refreshTakes()
            }
        }
        writeShelfStatus()
    }

    /// Moves the take folder to the Trash, where Finder can put it back. Its exports stay. The open
    /// take is closed without saving first, then the take below it opens.
    private func trash(_ entry: TakeEntry) {
        let folder = entry.folder
        let wasOpen = isOpen(folder)
        let next = TakesSidebarModel.neighbor(of: folder, in: screen.entries)
        if wasOpen {
            saveTask?.cancel()
            saveTask = nil
            preview.pause()
        }
        do {
            try store.moveToTrash(folder)
        } catch {
            log.error("moving take \(folder.lastPathComponent) to the Trash failed: \(error.localizedDescription)")
            NSSound.beep()
            return
        }
        if case .ok(let take, _) = entry { screen.posters[take.id] = nil }
        screen.entries.removeAll { $0.folder.standardizedFileURL == folder.standardizedFileURL }
        if wasOpen {
            session.close()
            filmstripTask?.cancel()
            if let next {
                open(next)
            } else {
                screen.editor = nil
                preview.unload()
            }
        }
        refreshTakes()
        writeShelfStatus()
    }

    /// File > Move to Trash: the open take.
    func trashOpenTake() {
        if let folder, let entry = screen.entries.first(where: { isOpen($0.folder) && $0.folder == folder }) { trash(entry) }
    }

    private func isOpen(_ folder: URL) -> Bool {
        session.folder?.standardizedFileURL == folder.standardizedFileURL
    }

    private static func revealURL(_ entry: TakeEntry) -> URL {
        if case .ok(_, let folder) = entry { folder.appending(path: TakeStore.movieName) } else { entry.folder }
    }

    /// A new take from the recorder: give it the saved look and a poster, load it, then hand it to
    /// the corner card. The editor window comes forward only from the card, so a recording never
    /// steals focus from the app the owner is in.
    var onReceived: (Take, NSImage?) -> Void = { _, _ in }

    func received(_ take: Take) {
        var take = take
        let folder = store.folder(for: take.id)
        if take.look == Look(), settings.defaultLook != Look() {
            do {
                take.look = try store.applyDefaultLook(settings.defaultLook, to: folder)
            } catch {
                log.warning("default backdrop for \(take.id.uuidString) failed: \(error.localizedDescription)")
                take.look = settings.defaultLook
                take.look.background = settings.defaultLook.resolved(in: folder).background
            }
            save(take)
        }
        // Captions from the owner's voice start right away; the editor shows "Transcribing…" until then.
        if take.microphoneOffset != nil, take.captions == nil { studio.transcribe(take, folder: folder) }
        Task {
            await makePoster(take, folder: folder)
            await reloadTakes()
            open(folder: folder)
            onReceived(take, NSImage(contentsOf: folder.appending(path: TakeStore.posterName)))
        }
    }

    /// Zoom names read from the screen after the take was saved: into the open editor when it shows
    /// that take, otherwise into its take.json. A take moved to the Trash meanwhile is left alone.
    func applyZoomNames(_ updates: [ZoomNameUpdate], to id: UUID) {
        if let editor = screen.editor, editor.take.id == id { return editor.apply(updates) }
        let folder = store.folder(for: id)
        do {
            var take = try store.load(folder)
            guard take.apply(updates) else { return }
            try store.save(take)
            refreshTakes()
        } catch {
            log.warning("zoom names for \(id.uuidString) were not saved: \(error.localizedDescription)")
        }
    }

    /// From the corner card: the take it shows, in the editor, optionally straight into Export.
    func showTake(_ id: UUID, export: Bool) {
        let folder = store.folder(for: id)
        if session.folder?.standardizedFileURL != folder.standardizedFileURL { open(folder: folder) }
        showWindow()
        if export { showExport() }
    }

    /// Reads the take from disk (TakeSession), so reopening one keeps its saved edits. When the
    /// open take's edits cannot be saved, the owner keeps editing it or discards them and switches.
    private func open(folder: URL, discardingEdits: Bool = false) {
        saveTask?.cancel()
        saveTask = nil
        preview.pause()
        let editor: EditorModel
        do {
            editor = try session.open(folder: folder, discardingEdits: discardingEdits)
        } catch let failure as TakeSession.SaveFailed {
            log.error("saving take failed: \(failure.underlying.localizedDescription)")
            alertSaveFailed(failure.underlying, discard: { [weak self] in self?.open(folder: folder, discardingEdits: true) })
            return
        } catch {
            log.error("opening take \(folder.lastPathComponent) failed: \(error.localizedDescription)")
            refreshTakes()
            return
        }
        loadFilmstrip(editor.take, folder: folder)
        screen.editor = editor
        preview.load(editor: editor, folder: folder)
        watchEdits(editor)
    }

    /// The poster stands in until the timeline's stills are decoded, a few hundred ms for most takes.
    private func loadFilmstrip(_ take: Take, folder: URL) {
        filmstripTask?.cancel()
        filmstrip.frames = screen.posters[take.id].map { [$0] } ?? []
        let movie = folder.appending(path: TakeStore.movieName)
        let times = Filmstrip.times(duration: take.duration, count: Filmstrip.count)
        filmstripTask = Task { [weak self] in
            let stills = await Self.stills(of: movie, at: times)
            guard !Task.isCancelled, let self, self.screen.editor?.take.id == take.id, !stills.isEmpty else { return }
            self.filmstrip.frames = stills.map { Image(decorative: $0, scale: 1) }
        }
    }

    /// Square stills cut from the middle of each frame, small enough for a timeline tile.
    nonisolated private static func stills(of movie: URL, at times: [Double]) async -> [CGImage] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
        generator.maximumSize = CGSize(width: 240, height: 240)
        let tolerance = CMTime(value: 1, timescale: 4)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        var stills: [CGImage] = []
        for t in times {
            if Task.isCancelled { return [] }
            guard let image = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image else { return [] }
            let side = min(image.width, image.height)
            let square = CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2, width: side, height: side)
            stills.append(image.cropping(to: square) ?? image)
        }
        return stills
    }

    private func makePoster(_ take: Take, folder: URL) async {
        let url = folder.appending(path: TakeStore.posterName)
        do {
            try await PosterMaker.poster(movie: folder.appending(path: TakeStore.movieName), at: min(1, take.duration / 2), to: url)
            if let image = NSImage(contentsOf: url) { screen.posters[take.id] = Image(nsImage: image) }
        } catch {
            log.warning("poster for \(take.id.uuidString) failed: \(error.localizedDescription)")
        }
    }

    // MARK: Saving

    /// Saves half a second after the last edit, and rebuilds the preview the same way.
    private func watchEdits(_ editor: EditorModel) {
        let id = ObjectIdentifier(editor)
        withObservationTracking {
            _ = editor.take
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, let editor = self.screen.editor, ObjectIdentifier(editor) == id else { return }
                self.scheduleSave(editor)
                self.preview.takeChanged()
                self.watchEdits(editor)
            }
        }
    }

    private func scheduleSave(_ editor: EditorModel) {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Saves the open take and refreshes its sidebar entry, so its name and "exported" stay current.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        do {
            try session.save()
            saveFailureShown = false
        } catch is TakeStore.FolderGone {
            // Trashed in Finder while open: let it go rather than write it back.
            log.warning("the open take's folder is gone; closing it")
            session.close()
            filmstripTask?.cancel()
            screen.editor = nil
            preview.unload()
            refreshTakes()
            return
        } catch {
            log.error("saving take failed: \(error.localizedDescription)")
            if !saveFailureShown {
                saveFailureShown = true
                alertSaveFailed(error, discard: nil)
            }
        }
        refreshOpenEntry()
    }

    /// A sheet on the editor: the edits are still open and Dolly saves again on the next change.
    /// With `discard`, the owner can drop the edits and go on to the other take.
    private func alertSaveFailed(_ error: any Error, discard: (() -> Void)?) {
        guard let window, window.attachedSheet == nil else { return NSSound.beep() }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't save this take"
        alert.informativeText = "\(error.localizedDescription) Your edits are still open, and Dolly saves again after your next change."
        alert.addButton(withTitle: "Keep editing")
        if discard != nil { alert.addButton(withTitle: "Discard edits") }
        alert.beginSheetModal(for: window) { response in
            if response == .alertSecondButtonReturn { discard?() }
        }
    }

    private func save(_ take: Take) {
        do {
            try store.save(take)
        } catch {
            log.error("saving take \(take.id.uuidString) failed: \(error.localizedDescription)")
        }
    }

    /// From the Settings window, which owns only Show in Shelf and the Advanced switches; the rest
    /// may have changed elsewhere while it was open.
    func apply(_ settings: DollyCore.Settings) {
        let shelfChanged = settings.showInShelf != self.settings.showInShelf
        self.settings.showInShelf = settings.showInShelf
        self.settings.advanced = settings.advanced
        saveSettings()
        if shelfChanged { writeShelfStatus() }
    }

    /// The clips folder from Settings; the export sheet's Change… sets the same value.
    /// The Record bar's switches and devices, remembered for the next time it opens.
    func setRecordDevices(_ bar: RecordBarModel) {
        bar.store(in: &settings)
        saveSettings()
    }

    func setExportsFolder(_ path: String) {
        settings.exportsFolder = path
        saveSettings()
    }

    private func markAimHintSeen() {
        guard !settings.aimHintSeen else { return }
        settings.aimHintSeen = true
        saveSettings()
    }

    /// A picture in the look is copied out of this take, so each new take gets its own copy.
    private func useForNewTakes(_ look: Look) {
        do {
            settings.defaultLook = try folder.map { try store.saveDefaultBackdrop(look, from: $0) } ?? look
        } catch {
            log.warning("saving the default backdrop failed: \(error.localizedDescription)")
            var flat = look
            flat.background = Look.defaultBackground
            settings.defaultLook = flat
        }
        saveSettings()
    }

    private func saveSettings() {
        do {
            try settingsStore.save(settings)
        } catch {
            log.error("saving settings failed: \(error.localizedDescription)")
        }
    }

    // MARK: Edit menu

    func undo() { screen.editor?.undo() }
    func redo() { screen.editor?.redo() }
    func deleteSelected() {
        if let editor = screen.editor, let id = editor.selectedZoom { editor.remove(id) }
    }

    func revealTake() {
        if let folder { NSWorkspace.shared.activateFileViewerSelecting([folder.appending(path: TakeStore.movieName)]) }
    }

    func setExportFPS(_ fps: Int) {
        settings.exportFPS = fps
        saveSettings()
    }

}

/// The workspace with live views: the player on the stage, the timeline driving it.
private struct LiveWorkspace: View {
    let editor: EditorModel
    let preview: PreviewPlayer
    let studio: StudioTasks
    let filmstrip: Filmstrip?
    let actions: StudioActions

    var body: some View {
        let clicks = editor.pointer?.clicks ?? []
        EditorWorkspace(
            editor: editor,
            stage: AnyView(StageView(editor: editor, image: preview.aimImage, player: preview.player,
                                     isPlaying: preview.isPlaying, clicks: clicks,
                                     showsAimHint: !actions.aimHintSeen, aimed: actions.aimed,
                                     resized: { preview.stageResized($0) })),
            inspector: AnyView(StudioInspector(editor: editor, clicks: clicks, actions: actions,
                                               transcription: studio.status(editor.take.id))),
            timeline: AnyView(TimelineView(editor: editor, clickTimes: clicks.map(\.t), filmstrip: filmstrip,
                                           playback: preview, isPlaying: preview.isPlaying))
        )
    }
}
