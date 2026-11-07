import Foundation
import Testing
@testable import DollyCore
@testable import DollyUI

final class FakeExporter: ExportRunning, @unchecked Sendable {
    var fails = false
    var waits = false
    var failsOn: ShapePreset?
    var shapes: [ShapePreset] = []
    func export(_ plan: ExportPlan, takeFolder: URL, pointer: PointerPath?, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        shapes.append(plan.shape)
        progress(0.5)
        if plan.shape == failsOn { throw CocoaError(.fileWriteOutOfSpace) }
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

    @Test func escapeClosesWhenNotExporting() async {
        let (sheet, _) = model(FakeExporter())
        var closes = 0
        sheet.escape { closes += 1 }
        #expect(closes == 1)
        await sheet.export()
        sheet.escape { closes += 1 }
        #expect(closes == 2)
    }

    @Test func escapeStopsARunningExportAndKeepsTheSheet() async {
        let fake = FakeExporter()
        fake.waits = true
        let (sheet, _) = model(fake)
        let job = Task { await sheet.export() }
        try? await Task.sleep(for: .milliseconds(30))
        var closes = 0
        sheet.escape { closes += 1 }
        await job.value
        #expect(closes == 0)
        #expect(sheet.state == .ready)
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

    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "dolly-sheet-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func startsWithTheTakesShape() {
        var take = SyntheticTake.shelfDemo()
        take.shape = .portrait4x5
        let sheet = ExportSheetModel(editor: EditorModel(take: take, pointer: nil), takeFolder: URL(filePath: "/tmp/take"),
                                     folder: URL(filePath: "/tmp/out"), exporter: FakeExporter())
        #expect(sheet.shapes == [.portrait4x5])
    }

    @Test func exportsEveryCheckedShapeInOrder() async {
        let fake = FakeExporter()
        let (sheet, editor) = model(fake)
        sheet.toggle(.tall9x16)
        sheet.toggle(.square1x1)
        sheet.toggle(.square1x1)
        await sheet.export()
        #expect(fake.shapes == [.wide16x9, .tall9x16])
        guard case .done(let urls) = sheet.state else { Issue.record("state \(sheet.state)"); return }
        #expect(urls.map(\.lastPathComponent) == ["Shelf Tile Board demo 16x9.mp4", "Shelf Tile Board demo 9x16.mp4"])
        #expect(editor.take.exports.map(\.shape) == [.wide16x9, .tall9x16])
        #expect(sheet.progress[.tall9x16] == 1)
    }

    @Test func atLeastOneShapeStaysChecked() {
        let (sheet, _) = model(FakeExporter())
        sheet.toggle(.wide16x9)
        #expect(sheet.shapes == [.wide16x9])
    }

    @Test func writesSRTBesideEachClip() async throws {
        let out = try folder()
        defer { try? FileManager.default.removeItem(at: out) }
        var take = SyntheticTake.shelfDemo()
        take.name = "Demo"
        take.captions = SyntheticTake.shelfCaptions()
        take.captions?.saveSRT = true
        let editor = EditorModel(take: take, pointer: nil)
        let sheet = ExportSheetModel(editor: editor, takeFolder: URL(filePath: "/tmp/take"), folder: out, exporter: FakeExporter())
        sheet.toggle(.tall9x16)
        await sheet.export()
        let names = try FileManager.default.contentsOfDirectory(atPath: out.path).sorted()
        #expect(names == ["Demo 16x9.srt", "Demo 9x16.srt"])
        let srt = try String(contentsOf: out.appending(path: "Demo 16x9.srt"), encoding: .utf8)
        #expect(srt.hasPrefix("1\n00:00:00,400 --> 00:00:03,800\nThis is Shelf, my launcher for every app.\n"))
        #expect(sheet.state == .done([out.appending(path: "Demo 16x9.mp4"), out.appending(path: "Demo 9x16.mp4")]))
    }

    @Test func noSRTWhenTheSwitchIsOff() async throws {
        let out = try folder()
        defer { try? FileManager.default.removeItem(at: out) }
        var take = SyntheticTake.shelfDemo()
        take.captions = SyntheticTake.shelfCaptions()
        let sheet = ExportSheetModel(editor: EditorModel(take: take, pointer: nil), takeFolder: URL(filePath: "/tmp/take"), folder: out,
                                     exporter: FakeExporter())
        await sheet.export()
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path).isEmpty)
    }

    @Test func failedShapeStopsAndSays() async {
        let fake = FakeExporter()
        fake.failsOn = .tall9x16
        let (sheet, editor) = model(fake)
        sheet.toggle(.tall9x16)
        sheet.toggle(.original)
        await sheet.export()
        guard case .failed(let message) = sheet.state else { Issue.record("state \(sheet.state)"); return }
        #expect(message.hasPrefix("Couldn't export 9:16: "))
        #expect(fake.shapes == [.original, .wide16x9, .tall9x16])
        #expect(editor.take.exports.map(\.shape) == [.original, .wide16x9])
    }
}
