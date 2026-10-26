import DollyCore
import Observation
import SwiftUI

/// The export sheet's state (spec 7). M1 exports the 16:9 shape; the plate row is ready for more.
@MainActor
@Observable
public final class ExportSheetModel {
    public enum State: Hashable {
        case ready
        case exporting(progress: Double)
        case done([URL])
        case failed(String)
    }

    public var state: State = .ready
    public var fps = 60
    public var folder: URL
    public let shape = ShapePreset.wide16x9
    @ObservationIgnored public var onExported: ([URL]) -> Void = { _ in }
    @ObservationIgnored let editor: EditorModel
    @ObservationIgnored let takeFolder: URL
    @ObservationIgnored let exporter: any ExportRunning
    @ObservationIgnored private var job: Task<URL, any Error>?

    public init(editor: EditorModel, takeFolder: URL, folder: URL, exporter: any ExportRunning) {
        self.editor = editor
        self.takeFolder = takeFolder
        self.folder = folder
        self.exporter = exporter
    }

    public static func doneText(_ count: Int) -> String { "Saved \(count) \(count == 1 ? "file" : "files")" }

    public var plan: ExportPlan { ExportPlan(take: editor.take, shape: shape, fps: fps, folder: folder) }

    public func export() async {
        state = .exporting(progress: 0)
        let plan = plan, folder = takeFolder, pointer = editor.pointer, exporter = exporter
        let job = Task {
            try await exporter.export(plan, takeFolder: folder, pointer: pointer) { value in
                Task { @MainActor in if case .exporting = self.state { self.state = .exporting(progress: value) } }
            }
        }
        self.job = job
        do {
            let url = try await job.value
            editor.recordExport(ExportRecord(shape: shape, url: url, date: Date()))
            state = .done([url])
            onExported([url])
        } catch is CancellationError {
            state = .ready
        } catch {
            state = job.isCancelled ? .ready : .failed("Couldn't export: \(error.localizedDescription)")
        }
        self.job = nil
    }

    public func cancel() { job?.cancel() }
}

/// The sheet (spec 7): the shape as a plate with the frame at the playhead, quality, folder, the
/// length line, Export. Progress follows real bytes with no easing; "Saved" fades in 160 ms.
public struct ExportSheet: View {
    @Bindable var model: ExportSheetModel
    let poster: CGImage?
    let chooseFolder: () -> Void
    let copy: ([URL]) -> Void
    let reveal: ([URL]) -> Void
    let close: () -> Void
    @Environment(\.dollyShot) private var shot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: ExportSheetModel, poster: CGImage?, chooseFolder: @escaping () -> Void, copy: @escaping ([URL]) -> Void,
                reveal: @escaping ([URL]) -> Void, close: @escaping () -> Void) {
        self.model = model
        self.poster = poster
        self.chooseFolder = chooseFolder
        self.copy = copy
        self.reveal = reveal
        self.close = close
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export").font(Theme.Font.display(18)).accessibilityAddTraits(.isHeader)
            plate
            settings
            footer
        }
        .padding(24)
        .frame(width: 520)
        .foregroundStyle(Theme.ink.color)
        .background(Theme.sheet.color)
        .animation(reduceMotion ? nil : .easeOut(duration: Theme.Motion.saved), value: model.state)
    }

    private var plate: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let poster { Image(decorative: poster, scale: 1).resizable().aspectRatio(16 / 9, contentMode: .fit) } else {
                    Rectangle().fill(Theme.raised.color).aspectRatio(16 / 9, contentMode: .fit)
                }
            }
            .frame(width: 280)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 8) {
                Image(systemName: "checkmark.square.fill").foregroundStyle(Theme.ink.color)
                Text(model.shape.label).font(Theme.Font.display(14))
                Text(verbatim: "\(model.shape.pixelSize.width) × \(model.shape.pixelSize.height)").font(Theme.Font.meta)
                    .monospacedDigit().foregroundStyle(Theme.muted.color)
            }
            .accessibilityElement(children: .combine)
            if case .exporting(let progress) = model.state { progressBar(progress) }
        }
    }

    private func progressBar(_ progress: Double) -> some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.active.color)
                    Capsule().fill(Theme.ink.color).frame(width: geo.size.width * progress)
                }
            }
            .frame(width: 220, height: 6)
            Text("\(Int((progress * 100).rounded()))%").font(Theme.Font.meta).monospacedDigit().foregroundStyle(Theme.muted.color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exporting")
        .accessibilityValue("\(Int((progress * 10).rounded() * 10)) percent")
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Quality").font(Theme.Font.bodyMedium)
                Spacer()
                if shot {
                    ShotControls.segmented(["60 fps", "30 fps"], selected: model.fps == 60 ? 0 : 1).frame(width: 180)
                } else {
                    Picker("Quality", selection: $model.fps) {
                        Text("60 fps").tag(60)
                        Text("30 fps").tag(30)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                }
            }
            HStack {
                Text("Save to").font(Theme.Font.bodyMedium)
                Spacer()
                Text(model.folder.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(Theme.Font.body).foregroundStyle(Theme.muted.color).lineLimit(1).truncationMode(.middle)
                Button("Change…", action: chooseFolder).buttonStyle(DollyButtonStyle())
            }
            Text(PlatformLimits.lengthLine(model.editor.take.trim.upperBound - model.editor.take.trim.lowerBound))
                .font(Theme.Font.body).monospacedDigit().foregroundStyle(Theme.muted.color)
        }
        .disabled(isExporting)
    }

    private var isExporting: Bool { if case .exporting = model.state { true } else { false } }

    @ViewBuilder private var footer: some View {
        HStack(spacing: 8) {
            switch model.state {
            case .ready:
                Spacer()
                Button("Cancel", action: close).buttonStyle(DollyButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Export") { Task { await model.export() } }.buttonStyle(DollyButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
            case .exporting:
                Spacer()
                Button("Cancel") { model.cancel() }.buttonStyle(DollyButtonStyle()).keyboardShortcut(.cancelAction)
            case .done(let urls):
                Text(ExportSheetModel.doneText(urls.count)).font(Theme.Font.bodyMedium).transition(.opacity)
                Spacer()
                Button("Copy") { copy(urls) }.buttonStyle(DollyButtonStyle())
                Button("Show in Finder") { reveal(urls) }.buttonStyle(DollyButtonStyle())
                Button("Done", action: close).buttonStyle(DollyButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
            case .failed(let message):
                Text(message).font(Theme.Font.body).foregroundStyle(Theme.record.color).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Close", action: close).buttonStyle(DollyButtonStyle())
                Button("Try again") { Task { await model.export() } }.buttonStyle(DollyButtonStyle(kind: .primary))
            }
        }
    }
}
