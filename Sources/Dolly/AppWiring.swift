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
    private var window: NSWindow?
    private let session: TakeSession
    private var filmstrip: Image?
    private var saveTask: Task<Void, Never>?

    init(paths: DollyPaths, settings: DollyCore.Settings, log: Log) {
        self.paths = paths
        self.settings = settings
        self.log = log
        store = TakeStore(paths: paths)
        session = TakeSession(store: store)
        settingsStore = SettingsStore(paths: paths)
        screen = EditorScreenModel(entries: [], totalBytes: 0, editor: nil, recordShortcut: settings.hotkey.displayString)
        super.init()
        screen.onRecord = { [weak self] in self?.onRecord() }
        screen.onExport = { [weak self] in self?.showExport() }
        screen.onSelect = { [weak self] entry in self?.open(entry) }
        reloadTakes()
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
        let preview = preview
        let root = EditorView(model: screen) { [weak self] editor in
            AnyView(LiveWorkspace(editor: editor, preview: preview, filmstrip: self?.filmstrip,
                                  useForNewTakes: { look in self?.useForNewTakes(look) }))
        }
        window.contentView = NSHostingView(rootView: root)
        window.center()
        window.setFrameAutosaveName("DollyEditor")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        preview.pause()
        saveNow()
    }

    // MARK: Takes

    /// The take being recorded has no take.json yet; it is left out until it is saved.
    var recordingFolder: () -> URL? = { nil }

    func reloadTakes() {
        let recording = recordingFolder()?.standardizedFileURL
        screen.entries = store.list().filter { $0.folder.standardizedFileURL != recording }
        screen.totalBytes = store.totalBytes()
        for case .ok(let take, let folder) in screen.entries where screen.posters[take.id] == nil {
            if let image = NSImage(contentsOf: folder.appending(path: TakeStore.posterName)) {
                screen.posters[take.id] = Image(nsImage: image)
            }
        }
    }

    func open(_ entry: TakeEntry) {
        switch entry {
        case .ok(_, let folder): open(folder: folder)
        case .broken(let folder, _): NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
    }

    func openLatest() {
        reloadTakes()
        if let first = screen.entries.first(where: { if case .ok = $0 { true } else { false } }) { open(first) }
        showWindow()
    }

    /// A new take from the recorder: give it the saved look and a poster, load it, then hand it to
    /// the corner card. The editor window comes forward only from the card, so a recording never
    /// steals focus from the app the owner is in.
    var onReceived: (Take, NSImage?) -> Void = { _, _ in }

    func received(_ take: Take) {
        var take = take
        if take.look == Look(), settings.defaultLook != Look() {
            take.look = settings.defaultLook
            save(take)
        }
        let folder = store.folder(for: take.id)
        Task {
            await makePoster(take, folder: folder)
            reloadTakes()
            open(folder: folder)
            onReceived(take, NSImage(contentsOf: folder.appending(path: TakeStore.posterName)))
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
            reloadTakes()
            return
        }
        filmstrip = screen.posters[editor.take.id]
        screen.editor = editor
        preview.load(editor: editor, folder: folder)
        watchEdits(editor)
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

    /// Saves the open take and refreshes the sidebar, so its names and "exported" stay current.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        do {
            try session.save()
        } catch {
            log.error("saving take failed: \(error.localizedDescription)")
        }
        reloadTakes()
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
    func setExportsFolder(_ path: String) {
        settings.exportsFolder = path
        saveSettings()
    }

    private func useForNewTakes(_ look: Look) {
        settings.defaultLook = look
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
        if let editor = screen.editor, let id = editor.selection { editor.remove(id) }
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
        Task { presentExport(poster: await preview.outputStill()) }
    }

    private func presentExport(poster: CGImage?) {
        guard let editor = screen.editor, let folder, let window, window.attachedSheet == nil else { return }
        let model = ExportSheetModel(editor: editor, takeFolder: folder, folder: exportsFolder, exporter: Exporter())
        model.fps = settings.exportFPS
        model.onExported = { [weak self, weak model] _ in
            if let fps = model?.fps, fps != self?.settings.exportFPS { self?.setExportFPS(fps) }
            self?.exported()
        }
        let sheet = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        let view = ExportSheet(
            model: model, poster: poster,
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
        sheet.contentView = NSHostingView(rootView: view)
        sheet.setContentSize(sheet.contentView?.fittingSize ?? CGSize(width: 520, height: 520))
        window.beginSheet(sheet)
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
    func writeShelfStatus() {
        var newest: (take: Take, folder: URL, date: Date)?
        for case .ok(let take, let folder) in store.list() {
            guard let date = take.exports.map(\.date).max() else { continue }
            if date > newest?.date ?? .distantPast { newest = (take, folder, date) }
        }
        let latest = newest.map { item in
            ShelfLatest(title: item.take.name, lengthSeconds: item.take.trim.upperBound - item.take.trim.lowerBound,
                        exportedShapes: Array(Set(item.take.exports.map(\.shape.label))).sorted(), exportedAt: item.date)
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let writer = ShelfStatusWriter(directory: paths.shelfStatusFolder, appVersion: version)
        do {
            try writer.write(latest: latest, poster: newest?.folder.appending(path: TakeStore.posterName),
                             showInShelf: settings.showInShelf)
        } catch {
            log.warning("Shelf status write failed: \(error.localizedDescription)")
        }
    }
}

/// The workspace with live views: the player on the stage, the timeline driving it.
private struct LiveWorkspace: View {
    let editor: EditorModel
    let preview: PreviewPlayer
    let filmstrip: Image?
    let useForNewTakes: (Look) -> Void

    var body: some View {
        let clicks = editor.pointer?.clicks ?? []
        EditorWorkspace(
            editor: editor,
            stage: AnyView(StageView(editor: editor, image: preview.aimImage, player: preview.player,
                                     isPlaying: preview.isPlaying, clicks: clicks)),
            inspector: AnyView(InspectorView(editor: editor, clicks: clicks, useForNewTakes: useForNewTakes)),
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
    /// Composition time 0 is the trim start.
    @ObservationIgnored private var offset = 0.0
    @ObservationIgnored private var lastSeek = -1.0

    func load(editor: EditorModel, folder: URL) {
        self.editor = editor
        self.folder = folder
        aimImage = nil
        recordingFrame = nil
        movie = folder.appending(path: TakeStore.movieName)
        rebuild(after: .zero)
        watchPlayhead(editor)
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
            do {
                let built = try await PlayerItemFactory.composition(take: take, folder: folder, shape: .wide16x9, fps: 60,
                                                                    pointer: editor.pointer)
                guard !Task.isCancelled else { return }
                install(AVPlayerItem(asset: built.asset), videoComposition: built.videoComposition, take: take)
            } catch {
                if let timeObserver { player?.removeTimeObserver(timeObserver) }
                timeObserver = nil
                player = nil
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
            _ = editor.selection
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
        guard let editor, editor.selection != nil, let movie else { return }
        frameTask?.cancel()
        let t = editor.playhead
        frameTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled, let image = await Self.frame(of: movie, at: t) else { return }
            guard let self, !Task.isCancelled else { return }
            recordingFrame = image
            renderAim()
        }
    }

    private func renderAim() {
        guard let editor, let recordingFrame else { return }
        aimImage = StillRenderer.render(take: editor.take, recording: recordingFrame, camera: nil, pointer: nil, ring: nil)
    }

    /// The output at the playhead, for the export sheet's plate.
    func outputStill() async -> CGImage? {
        guard let editor, let movie else { return nil }
        let take = editor.take
        let t = editor.playhead
        guard let frame = await Self.frame(of: movie, at: t) else { return nil }
        let layout = ShapeLayout(shape: .wide16x9, recordingSize: take.size, padding: take.look.padding)
        let pointer = editor.pointer
        let path = CameraPath(zooms: take.zooms, layout: layout, pointer: pointer.map { p in { @Sendable t in p.position(at: t) } },
                              duration: take.duration)
        return StillRenderer.render(take: take, recording: frame, camera: path.camera(at: t),
                                    pointer: pointer?.position(at: t).map { ($0, pointer?.shape(at: t) ?? .arrow) },
                                    ring: pointer?.ring(at: t).map { ($0.center, $0.progress) })
    }

    /// One recording frame, within a frame of `t`.
    nonisolated private static func frame(of movie: URL, at t: Double) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
        let tolerance = CMTime(value: 1, timescale: 60)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        return try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
    }
}
