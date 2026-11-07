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

    private let paths: DollyPaths
    private let store: TakeStore
    private let settingsStore: SettingsStore
    private let log: Log
    private(set) var settings: DollyCore.Settings
    private let preview = PreviewPlayer()
    private let studio: StudioTasks
    private var window: NSWindow?
    private var aside = EditorStepAside()
    private let session: TakeSession
    private let filmstrip = Filmstrip()
    private var filmstripTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var reloadNumber = 0
    private var shelfNumber = 0
    private weak var exportModel: ExportSheetModel?

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
    private var folder: URL? { session.folder }

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

    /// Reads the take from disk (TakeSession), so reopening one keeps its saved edits.
    private func open(folder: URL) {
        saveTask?.cancel()
        saveTask = nil
        preview.pause()
        let editor: EditorModel
        do {
            editor = try session.open(folder: folder)
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
        } catch {
            log.error("saving take failed: \(error.localizedDescription)")
        }
        refreshOpenEntry()
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

    // MARK: Export

    private var exportsFolder: URL {
        settings.exportsFolder.map { URL(filePath: $0, directoryHint: .isDirectory) } ?? paths.exportsFolder
    }

    func showExport() {
        guard screen.editor != nil, let window, window.attachedSheet == nil else { return }
        preview.pause()
        Task { presentExport(posters: await preview.outputStills()) }
    }

    private func presentExport(posters: [ShapePreset: CGImage]) {
        guard let editor = screen.editor, let folder, let window, window.attachedSheet == nil else { return }
        let model = ExportSheetModel(editor: editor, takeFolder: folder, folder: exportsFolder, exporter: Exporter())
        exportModel = model
        model.fps = settings.exportFPS
        model.onExported = { [weak self, weak model] _ in
            if let fps = model?.fps, fps != self?.settings.exportFPS { self?.setExportFPS(fps) }
            self?.exported()
        }
        let sheet = SheetWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        let view = ExportSheet(
            model: model, posters: posters,
            chooseFolder: { [weak self, weak sheet] in
                guard let self, let sheet else { return }
                self.chooseFolder(for: model, over: sheet)
            },
            copy: { Pasteboard.copyFiles($0) },
            reveal: { NSWorkspace.shared.activateFileViewerSelecting($0) },
            close: { [weak window, weak sheet] in
                if let sheet { window?.endSheet(sheet) }
            }
        )
        sheet.onCancel = { [weak window, weak sheet, weak model] in
            model?.escape { if let sheet { window?.endSheet(sheet) } }
        }
        sheet.contentView = NSHostingView(rootView: view.focusEffectDisabled())
        sheet.setContentSize(sheet.contentView?.fittingSize ?? CGSize(width: 520, height: 520))
        window.beginSheet(sheet)
    }

    var isExporting: Bool { exportModel?.isExporting ?? false }

    /// Quit: stops a running export and waits for it to clean up.
    func stopExportForQuit() async {
        await exportModel?.stopForQuit()
    }

    private func chooseFolder(for model: ExportSheetModel, over sheet: NSWindow) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = model.folder
        panel.prompt = "Choose"
        panel.beginSheetModal(for: sheet) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            model.folder = url
            settings.exportsFolder = url.path(percentEncoded: false)
            saveSettings()
        }
    }

    private func exported() {
        saveNow()
        writeShelfStatus()
    }

    func setExportFPS(_ fps: Int) {
        settings.exportFPS = fps
        saveSettings()
    }

    // MARK: Shelf

    /// The newest exported take, or none. Called after every export and once at launch, so the
    /// poster is removed when "Show in Shelf" is off.
    /// Reads every take off the main actor; a newer call wins over one still reading.
    func writeShelfStatus() {
        shelfNumber += 1
        let number = shelfNumber
        let store = store, showInShelf = settings.showInShelf
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let writer = ShelfStatusWriter(directory: paths.shelfStatusFolder, appVersion: version)
        Task {
            let newest = await Task.detached { Self.newestExport(in: store.list()) }.value
            guard number == shelfNumber else { return }
            let latest = newest.map { item in
                ShelfLatest(title: item.take.name, lengthSeconds: item.take.trim.upperBound - item.take.trim.lowerBound,
                            exportedShapes: Array(Set(item.take.exports.map(\.shape.label))).sorted(), exportedAt: item.date)
            }
            do {
                try writer.write(latest: latest, poster: newest?.folder.appending(path: TakeStore.posterName), showInShelf: showInShelf)
            } catch {
                log.warning("Shelf status write failed: \(error.localizedDescription)")
            }
        }
    }

    nonisolated private static func newestExport(in entries: [TakeEntry]) -> (take: Take, folder: URL, date: Date)? {
        var newest: (take: Take, folder: URL, date: Date)?
        for case .ok(let take, let folder) in entries {
            guard let date = take.exports.map(\.date).max() else { continue }
            if date > newest?.date ?? .distantPast { newest = (take, folder, date) }
        }
        return newest
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

/// The preview (spec 5.2): an AVPlayer on the same composition the exporter uses, kept in step
/// with the editor's playhead, plus the recording frame at the playhead for Aim mode.
@MainActor
@Observable
final class PreviewPlayer: PlaybackControlling {
    private(set) var player: AVPlayer?
    private(set) var isPlaying = false
    /// The recording at 1x with the look, for Aim mode.
    private(set) var aimImage: CGImage?

    @ObservationIgnored private weak var editor: EditorModel?
    @ObservationIgnored private var folder: URL?
    @ObservationIgnored private var movie: URL?
    @ObservationIgnored private var recordingFrame: CGImage?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    @ObservationIgnored private var frameTask: Task<Void, Never>?
    /// The player item's asset; kept while an edit leaves its inputs alone.
    @ObservationIgnored private var takeAsset: PlayerItemFactory.TakeAsset?
    /// Composition time 0 is the trim start.
    @ObservationIgnored private var offset = 0.0
    @ObservationIgnored private var lastSeek = -1.0
    /// The stage's size in points, from StageView; the Aim still is drawn at about this size.
    @ObservationIgnored private var stagePoints = CGSize.zero
    @ObservationIgnored private var frameNumber = 0
    @ObservationIgnored private var aimRequested: AimKey?
    @ObservationIgnored private var aimRenderer: LatestOnly<AimRequest, AimResult>?

    private struct AimKey: Equatable {
        let inputs: AimInputs
        let frame: Int
        let scale: Double
    }

    private struct AimRequest: Sendable {
        let take: Take
        let folder: URL?
        let recording: CGImage
        let scale: Double
    }

    private struct AimResult: Sendable {
        let image: CGImage?
        let takeID: UUID
    }

    init() {
        aimRenderer = LatestOnly(work: { request in
            AimResult(image: StillRenderer.render(take: request.take, folder: request.folder, recording: request.recording,
                                                  camera: nil, pointer: nil, ring: nil, scale: request.scale),
                      takeID: request.take.id)
        }, deliver: { [weak self] result in
            // A still from the take that was open before never replaces this one's.
            guard let self, let image = result.image, self.editor?.take.id == result.takeID else { return }
            self.aimImage = image
        })
    }

    func load(editor: EditorModel, folder: URL) {
        self.editor = editor
        self.folder = folder
        resetAim()
        takeAsset = nil
        movie = folder.appending(path: TakeStore.movieName)
        rebuild(after: .zero)
        watchPlayhead(editor)
    }

    /// From StageView. A bigger stage draws the Aim still again, a smaller one keeps it.
    func stageResized(_ size: CGSize) {
        stagePoints = size
        if editor?.selectedZoom != nil { renderAim() }
    }

    private func resetAim() {
        aimRenderer?.cancel()
        aimRequested = nil
        aimImage = nil
        recordingFrame = nil
    }

    /// The open take went to the Trash and no other take is left to show.
    func unload() {
        pause()
        rebuildTask?.cancel()
        frameTask?.cancel()
        player?.replaceCurrentItem(with: nil)
        editor = nil
        folder = nil
        movie = nil
        takeAsset = nil
        resetAim()
    }

    func takeChanged() {
        rebuild(after: .milliseconds(150))
        renderAim()
    }

    // MARK: PlaybackControlling

    func togglePlay() {
        isPlaying ? pause() : play(rate: 1)
    }

    func shuttle(_ rate: Double) {
        rate == 0 ? pause() : play(rate: rate)
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    private func play(rate: Double) {
        guard let player, let editor, let item = player.currentItem else { return }
        if rate < 0, !item.canPlayReverse {
            editor.playhead = max(editor.playhead - 1, editor.take.trim.lowerBound)
            return
        }
        if rate > 0, editor.playhead >= editor.take.trim.upperBound - 0.05 {
            editor.playhead = editor.take.trim.lowerBound
            seek(to: editor.playhead)
        }
        player.rate = Float(rate)
        isPlaying = true
    }

    // MARK: Player item

    private func rebuild(after delay: Duration) {
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self, let editor, let folder else { return }
            let take = editor.take
            // Twice the canvas on a Retina screen: the stage is wider than 1080p there, and a zoom
            // would otherwise show a stretched frame instead of the recording's own pixels.
            let scale = min(NSScreen.main?.backingScaleFactor ?? 1, 2)
            do {
                // Look and zoom edits keep the asset and the item; only the compositor's instruction changes.
                if let kept = takeAsset, kept.inputs == take.compositionInputs, let item = player?.currentItem {
                    let composition = await PlayerItemFactory.videoComposition(take: take, folder: folder, asset: kept,
                                                                               shape: take.currentShape, fps: 60,
                                                                               pointer: editor.pointer, renderScale: scale)
                    guard !Task.isCancelled else { return }
                    item.videoComposition = composition
                    if !isPlaying { seek(to: editor.playhead, force: true) }
                    return
                }
                let built = try await PlayerItemFactory.asset(take: take, folder: folder)
                let composition = await PlayerItemFactory.videoComposition(take: take, folder: folder, asset: built,
                                                                           shape: take.currentShape, fps: 60,
                                                                           pointer: editor.pointer, renderScale: scale)
                guard !Task.isCancelled else { return }
                takeAsset = built
                install(AVPlayerItem(asset: built.asset), videoComposition: composition, take: take)
            } catch {
                if let timeObserver { player?.removeTimeObserver(timeObserver) }
                timeObserver = nil
                player = nil
                takeAsset = nil
            }
        }
    }

    private func install(_ item: AVPlayerItem, videoComposition: AVVideoComposition, take: Take) {
        item.videoComposition = videoComposition
        offset = take.trim.lowerBound
        let wasPlaying = isPlaying
        let player = player ?? makePlayer()
        player.replaceCurrentItem(with: item)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item,
                                                             queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isPlaying = false }
        }
        if let editor { seek(to: editor.playhead, force: true) }
        if wasPlaying { player.play() }
    }

    private func makePlayer() -> AVPlayer {
        let player = AVPlayer()
        player.actionAtItemEnd = .pause
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying, let editor = self.editor else { return }
                let t = self.offset + time.seconds
                self.lastSeek = t
                editor.playhead = t
            }
        }
        self.player = player
        return player
    }

    private func seek(to t: Double, force: Bool = false) {
        guard let player, force || abs(t - lastSeek) > 0.0005 else { return }
        lastSeek = t
        let time = CMTime(seconds: max(t - offset, 0), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Scrubbing while paused moves the player; while playing the player moves the playhead.
    private func watchPlayhead(_ editor: EditorModel) {
        let id = ObjectIdentifier(editor)
        withObservationTracking {
            _ = editor.playhead
            _ = editor.selectedZoom
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, let editor = self.editor, ObjectIdentifier(editor) == id else { return }
                if !self.isPlaying {
                    self.seek(to: editor.playhead)
                    self.refreshFrame()
                } else if abs(editor.playhead - self.lastSeek) > 0.05 {
                    // A click on the ruler while playing: the player jumps there and plays on.
                    self.seek(to: editor.playhead, force: true)
                }
                self.watchPlayhead(editor)
            }
        }
    }

    // MARK: Frames

    private func refreshFrame() {
        guard let editor, editor.selectedZoom != nil, let movie else { return }
        frameTask?.cancel()
        let t = editor.playhead
        // The recording never needs more pixels than the canvas it is drawn into.
        let canvas = editor.take.currentShape.pixelSize(recording: editor.take.size)
        let limit = CGSize(width: canvas.width, height: canvas.height)
        frameTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled, let image = await Self.frame(of: movie, at: t, maximumSize: limit) else { return }
            guard let self, !Task.isCancelled else { return }
            recordingFrame = image
            frameNumber += 1
            renderAim()
        }
    }

    /// Draws the Aim still off the main actor at the stage's size. Zoom edits (aim, depth) do not
    /// change it, so only a new frame, a look edit or a bigger stage draws again; the old still
    /// stays up until the new one is ready.
    private func renderAim() {
        guard let editor, let recordingFrame, let aimRenderer else { return }
        let take = editor.take
        let canvas = take.currentShape.pixelSize(recording: take.size)
        let backing = NSScreen.main?.backingScaleFactor ?? 2
        let stage = CGSize(width: stagePoints.width * backing, height: stagePoints.height * backing)
        let scale = StillRenderer.previewScale(canvas: CGSize(width: canvas.width, height: canvas.height), stagePixels: stage)
        let key = AimKey(inputs: take.aimInputs, frame: frameNumber, scale: scale)
        // A smaller stage keeps the sharper still it has.
        if let last = aimRequested, last.inputs == key.inputs, last.frame == key.frame, last.scale >= key.scale { return }
        aimRequested = key
        aimRenderer.submit(AimRequest(take: take, folder: folder, recording: recordingFrame, scale: scale))
    }

    /// The output at the playhead in every shape, for the export sheet's plates.
    func outputStills() async -> [ShapePreset: CGImage] {
        guard let editor, let movie, let folder else { return [:] }
        let take = editor.take
        let t = editor.playhead
        guard let frame = await Self.frame(of: movie, at: t) else { return [:] }
        var cameraFrame: CGImage?
        if let camera = take.camera {
            cameraFrame = await Self.frame(of: folder.appending(path: camera.file), at: max(t - camera.startOffset, 0))
        }
        let pointer = editor.pointer
        var stills: [ShapePreset: CGImage] = [:]
        for shape in ShapePreset.allCases {
            let layout = ShapeLayout(shape: shape, recordingSize: take.size, padding: take.look.padding)
            let path = CameraPath(zooms: take.zooms, layout: layout, pointer: pointer.map { p in { @Sendable t in p.position(at: t) } },
                                  duration: take.duration)
            stills[shape] = StillRenderer.render(take: take, folder: folder, shape: shape, recording: frame, camera: path.camera(at: t),
                                                 pointer: pointer?.position(at: t).map { ($0, pointer?.shape(at: t) ?? .arrow) },
                                                 ring: pointer?.ring(at: t).map { ($0.center, $0.progress) },
                                                 cameraFrame: cameraFrame, at: t, depthProgress: path.depthProgress(at: t))
        }
        return stills
    }

    /// One recording frame, within a frame of `t`, no bigger than `maximumSize` when given.
    nonisolated private static func frame(of movie: URL, at t: Double, maximumSize: CGSize? = nil) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
        if let maximumSize { generator.maximumSize = maximumSize }
        let tolerance = CMTime(value: 1, timescale: 60)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        return try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
    }
}
