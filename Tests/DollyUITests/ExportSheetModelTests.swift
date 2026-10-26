import Foundation
import Testing
@testable import DollyCore
@testable import DollyUI

final class FakeExporter: ExportRunning, @unchecked Sendable {
    var fails = false
    var waits = false
    func export(_ plan: ExportPlan, takeFolder: URL, pointer: PointerPath?, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        progress(0.5)
        if waits {
            while true {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        if fails { throw CocoaError(.fileWriteOutOfSpace) }
        progress(1)
        return plan.outputURL(existing: [])
    }
}

@MainActor @Suite struct ExportSheetModelTests {
    func model(_ exporter: FakeExporter) -> (ExportSheetModel, EditorModel) {
        let editor = EditorModel(take: SyntheticTake.shelfDemo(), pointer: nil)
        let sheet = ExportSheetModel(editor: editor, takeFolder: URL(filePath: "/tmp/take"), folder: URL(filePath: "/tmp/out"),
                                     exporter: exporter)
        return (sheet, editor)
    }

    @Test func doneTextCountsFiles() {
        #expect(ExportSheetModel.doneText(1) == "Saved 1 file")
        #expect(ExportSheetModel.doneText(2) == "Saved 2 files")
    }

    @Test func recordsExportOnTake() async {
        let (sheet, editor) = model(FakeExporter())
        var exported: [URL] = []
        sheet.onExported = { exported = $0 }
        await sheet.export()
        #expect(sheet.state == .done([URL(filePath: "/tmp/out/Shelf Tile Board demo 16x9.mp4")]))
        #expect(editor.take.exports.count == 1 && editor.take.exports[0].shape == .wide16x9)
        #expect(exported.count == 1)
        #expect(!editor.canUndo)   // an export is not an edit
    }

    @Test func cancelLeavesNoRecord() async {
        let fake = FakeExporter()
        fake.waits = true
        let (sheet, editor) = model(fake)
        let job = Task { await sheet.export() }
        try? await Task.sleep(for: .milliseconds(30))
        sheet.cancel()
        await job.value
        #expect(sheet.state == .ready)
        #expect(editor.take.exports.isEmpty)
    }

    @Test func failureSaysWhy() async {
        let fake = FakeExporter()
        fake.fails = true
        let (sheet, _) = model(fake)
        await sheet.export()
        guard case .failed(let message) = sheet.state else { Issue.record("state \(sheet.state)"); return }
        #expect(message.hasPrefix("Couldn't export: "))
    }

    @Test func thirtyFPSGoesIntoThePlan() {
        let (sheet, _) = model(FakeExporter())
        sheet.fps = 30
        #expect(sheet.plan.fps == 30 && sheet.plan.shape == .wide16x9)
    }
}
