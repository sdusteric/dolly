import AppKit
import DollyCore
import DollyRender
import DollySystem
import DollyUI
import SwiftUI

/// The export sheet (spec 7) and the Shelf status written after each export.
extension EditorController {
    // MARK: Export

    var exportsFolder: URL {
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
            setExportsFolder(url.path(percentEncoded: false))
        }
    }

    private func exported() {
        saveNow()
        writeShelfStatus()
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
