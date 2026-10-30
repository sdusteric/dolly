import AppKit
import DollyCore
import DollySystem
import DollyUI
import SwiftUI

/// The real app: menus, the record hotkey, `dolly://` actions from Shelf, Sparkle, and the editor
/// and recording wiring. Shot mode never creates it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSWindowDelegate {
    private let paths = DollyPaths()
    private lazy var log = Log(paths: paths)
    private var editor: EditorController?
    private var recording: RecordingWiring?
    private var hotkeys: HotkeyCenter?
    private var updater: Updater?
    private var pendingURLs: [URL] = []
    private var settingsWindow: NSWindow?
    private var settingsModel: SettingsScreenModel?
    private let probe = ClickProbe()
    private let takeCard = TakeCard()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings: DollyCore.Settings
        do {
            settings = try SettingsStore(paths: paths).load()
        } catch {
            settings = DollyCore.Settings()
        }
        updater = Updater.make()
        let editor = EditorController(paths: paths, settings: settings, log: log)
        let recording = RecordingWiring(paths: paths, settings: settings)
        editor.onRecord = { [weak recording] in recording?.hotkeyPressed() }
        recording.onTake = { [weak editor] take in editor?.received(take) }
        recording.onChoosing = { [weak editor] in editor?.stepAside() }
        recording.onChoiceEnded = { [weak editor] started in
            if started { editor?.recordingStarted() } else { editor?.recordingCancelled() }
        }
        recording.onDevices = { [weak editor, weak recording] bar in
            guard let editor else { return }
            editor.setRecordDevices(bar)
            recording?.apply(editor.settings)
        }
        editor.onReceived = { [weak self, weak editor] take, poster in
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            self?.takeCard.show(TakeCardModel(take: take), poster: poster, on: screen,
                                edit: { editor?.showTake(take.id, export: false) },
                                export: { editor?.showTake(take.id, export: true) })
        }
        editor.recordingFolder = { [weak recording] in recording?.currentFolder }
        self.editor = editor
        self.recording = recording

        let hotkeys = HotkeyCenter { [weak self] press in
            if press.action == .record { self?.recording?.hotkeyPressed() }
        }
        for registration in hotkeys.register([.record: settings.hotkey]) where !registration.isRegistered {
            log.warning("record shortcut \(settings.hotkey.displayString) not registered: \(registration.message ?? "")")
        }
        self.hotkeys = hotkeys

        NSApp.mainMenu = makeMainMenu(shortcut: settings.hotkey)
        editor.writeShelfStatus()
        editor.openLatest()
        let urls = pendingURLs
        pendingURLs = []
        urls.forEach(handle)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard editor != nil else { return pendingURLs.append(contentsOf: urls) }
        urls.forEach(handle)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        editor?.showWindow()
        return true
    }

    /// Closing the editor keeps Dolly running so the record shortcut still works.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Quitting mid-recording (Quit, logout, a Sparkle update) finishes the take first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let recording, recording.isRecording else { return .terminateNow }
        Task {
            await recording.stopForQuit()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        editor?.saveNow()
        hotkeys?.unregisterAll()
    }

    // MARK: Shelf actions

    private func handle(_ url: URL) {
        guard let action = DollyURL(url) else {
            let host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host ?? ""
            log.warning("ignored dolly URL with host '\(String(host.prefix(40)))'")
            return
        }
        switch action {
        case .record: recording?.hotkeyPressed()
        case .openLatest: editor?.openLatest()
        case .checkForUpdates: updater?.checkForUpdates()
        }
    }

    // MARK: Settings

    /// Holding Option while opening Settings shows Advanced (the owner's spike switches).
    @objc func showSettings(_ sender: Any?) {
        guard let editor else { return }
        let advanced = AdvancedSettingsModel.showsAdvanced(optionHeld: NSEvent.modifierFlags.contains(.option))
        let model = settingsModel ?? SettingsScreenModel(settings: editor.settings, showsAdvanced: advanced,
                                                         takesFolder: (paths.takesFolder.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath,
                                                         defaultClipsFolder: paths.exportsFolder.path(percentEncoded: false))
        model.settings = editor.settings
        model.showsAdvanced = advanced
        model.revealTakes = { [paths] in NSWorkspace.shared.activateFileViewerSelecting([paths.takesFolder]) }
        model.revealClips = { [weak model] in
            guard let model else { return }
            let url = URL(filePath: model.settings.exportsFolder ?? model.defaultClipsFolder, directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        model.onClipsFolder = { [weak self] path in self?.editor?.setExportsFolder(path) }
        model.chooseClipsFolder = { [weak self, weak model] in
            guard let model, let window = self?.settingsWindow else { return }
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.directoryURL = URL(filePath: model.settings.exportsFolder ?? model.defaultClipsFolder, directoryHint: .isDirectory)
            panel.prompt = "Choose"
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                model.setClipsFolder(url.path(percentEncoded: false))
            }
        }
        model.onChange = { [weak self] settings in
            guard let self else { return }
            self.editor?.apply(settings)
            if let merged = self.editor?.settings { self.recording?.apply(merged) }
            if model.showsAdvanced { self.startProbe(model) }
        }
        settingsModel = model

        let window = settingsWindow ?? NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        if settingsWindow == nil {
            window.title = "Settings"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
        }
        window.setContentSize(window.contentView?.fittingSize ?? CGSize(width: 480, height: 240))
        if settingsWindow == nil { window.center() }
        settingsWindow = window
        advanced ? startProbe(model) : probe.stop()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func startProbe(_ model: SettingsScreenModel) {
        probe.start(source: model.settings.advanced.clickSource) { [weak model] point in
            model?.lastClick = (point, Date())
        }
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === settingsWindow { probe.stop() }
    }

    // MARK: Menu actions

    @objc func newRecording(_ sender: Any?) { recording?.hotkeyPressed() }
    @objc func exportTake(_ sender: Any?) { editor?.showExport() }
    @objc func showInFinder(_ sender: Any?) { editor?.revealTake() }
    @objc func showEditor(_ sender: Any?) { editor?.showWindow() }
    @objc func checkForUpdates(_ sender: Any?) { updater?.checkForUpdates() }

    /// Text fields keep their own undo; everything else undoes the take.
    @objc func undoEdit(_ sender: Any?) {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.undoManager?.undo() } else { editor?.undo() }
    }

    @objc func redoEdit(_ sender: Any?) {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.undoManager?.redo() } else { editor?.redo() }
    }

    @objc func deleteZoom(_ sender: Any?) { editor?.deleteSelected() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let editing = NSApp.keyWindow?.firstResponder is NSTextView
        let model = editor?.editor
        switch menuItem.action {
        case #selector(exportTake(_:)), #selector(showInFinder(_:)): return model != nil
        case #selector(undoEdit(_:)): return editing ? NSApp.keyWindow?.firstResponder?.undoManager?.canUndo == true : model?.canUndo == true
        case #selector(redoEdit(_:)): return editing ? NSApp.keyWindow?.firstResponder?.undoManager?.canRedo == true : model?.canRedo == true
        case #selector(deleteZoom(_:)): return !editing && model?.selectedZoom != nil
        case #selector(checkForUpdates(_:)): return updater != nil
        default: return true
        }
    }

    // MARK: Menus

    private func makeMainMenu(shortcut: HotkeyCombo) -> NSMenu {
        let main = NSMenu()

        let app = submenu(main, "Dolly")
        app.addItem(withTitle: "About Dolly", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(item("Check for Updates…", #selector(checkForUpdates(_:))))
        app.addItem(.separator())
        app.addItem(item("Settings…", #selector(showSettings(_:)), key: ","))
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Dolly", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Dolly", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let file = submenu(main, "File")
        let record = item("New Recording", #selector(newRecording(_:)), key: "r")
        record.keyEquivalentModifierMask = [.control, .option, .command]
        // The hotkey is global; the menu only shows it when it is still the default.
        if shortcut != .defaultRecord { record.keyEquivalent = "" }
        file.addItem(record)
        file.addItem(item("Export…", #selector(exportTake(_:)), key: "e"))
        file.addItem(item("Show in Finder", #selector(showInFinder(_:))))
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let edit = submenu(main, "Edit")
        edit.addItem(item("Undo", #selector(undoEdit(_:)), key: "z"))
        let redo = item("Redo", #selector(redoEdit(_:)), key: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(item("Delete Zoom", #selector(deleteZoom(_:))))
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let view = submenu(main, "View")
        let full = view.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        full.keyEquivalentModifierMask = [.command, .control]

        let window = submenu(main, "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(item("Editor", #selector(showEditor(_:)), key: "0"))
        window.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window

        NSApp.helpMenu = submenu(main, "Help")
        return main
    }

    private func submenu(_ main: NSMenu, _ title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        main.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = menu
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
}
