import DollyCore
import Observation
import SwiftUI

/// The export sheet's state (spec 7, studio spec item 5): the checked shapes, exported one after
/// another, each with an .srt beside it when the captions ask for one.
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
    /// Starts with the shape the stage shows; at least one stays checked.
    public private(set) var shapes: Set<ShapePreset>
    /// Each shape's own progress while exporting, for its plate.
    public private(set) var progress: [ShapePreset: Double] = [:]
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
        shapes = [editor.take.currentShape]
    }

    public static func doneText(_ count: Int) -> String { "Saved \(count) \(count == 1 ? "file" : "files")" }

    /// The checked shapes in the plates' order.
    public var ordered: [ShapePreset] { ShapePreset.allCases.filter(shapes.contains) }

    public func toggle(_ shape: ShapePreset) {
        if shapes.contains(shape) {
            if shapes.count > 1 { shapes.remove(shape) }
        } else {
            shapes.insert(shape)
        }
    }

    public func sizeText(_ shape: ShapePreset) -> String {
        let size = shape.pixelSize(recording: editor.take.size)
        return "\(size.width) × \(size.height)"
    }

    public func plan(for shape: ShapePreset) -> ExportPlan { ExportPlan(take: editor.take, shape: shape, fps: fps, folder: folder) }
    public var plan: ExportPlan { plan(for: ordered.first ?? editor.take.currentShape) }

    public func export() async {
        state = .exporting(progress: 0)
        progress = [:]
        let list = ordered
        var urls: [URL] = []
        for (i, shape) in list.enumerated() {
            let plan = plan(for: shape), folder = takeFolder, pointer = editor.pointer, exporter = exporter
            let count = Double(list.count)
            let job = Task {
                try await exporter.export(plan, takeFolder: folder, pointer: pointer) { value in
                    Task { @MainActor in
                        guard case .exporting = self.state, value > (self.progress[shape] ?? 0) else { return }
                        self.progress[shape] = value
                        self.state = .exporting(progress: (Double(i) + value) / count)
                    }
                }
            }
            self.job = job
            do {
                let url = try await job.value
                editor.recordExport(ExportRecord(shape: shape, url: url, date: Date()))
                progress[shape] = 1
                try writeSRT(beside: url)
                urls.append(url)
            } catch {
                self.job = nil
                if error is CancellationError || job.isCancelled {
                    state = .ready
                } else {
                    let what = list.count > 1 ? "Couldn't export \(shape.label)" : "Couldn't export"
                    state = .failed("\(what): \(error.localizedDescription)")
                }
                if !urls.isEmpty { onExported(urls) }
                return
            }
        }
        self.job = nil
        state = .done(urls)
        onExported(urls)
    }

    /// `<clip name>.srt` with the captions inside the trim, timed from the trim start.
    private func writeSRT(beside url: URL) throws {
        let take = editor.take
        guard let captions = take.captions, captions.saveSRT else { return }
        let items = captions.items.filter { $0.start < take.trim.upperBound && !$0.text.isEmpty }
        guard !items.isEmpty else { return }
        try SRT.text(items, trimStart: take.trim.lowerBound)
            .write(to: url.deletingPathExtension().appendingPathExtension("srt"), atomically: true, encoding: .utf8)
    }

    public func cancel() { job?.cancel() }
}

/// The sheet (spec 7): every shape as a plate with the frame at the playhead, quality, folder, the
/// length line, Export. Progress follows real bytes with no easing; "Saved" fades in 160 ms.
public struct ExportSheet: View {
    @Bindable var model: ExportSheetModel
    let posters: [ShapePreset: CGImage]
    let chooseFolder: () -> Void
    let copy: ([URL]) -> Void
    let reveal: ([URL]) -> Void
    let close: () -> Void
    @Environment(\.dollyShot) private var shot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: ExportSheetModel, posters: [ShapePreset: CGImage], chooseFolder: @escaping () -> Void,
                copy: @escaping ([URL]) -> Void, reveal: @escaping ([URL]) -> Void, close: @escaping () -> Void) {
        self.model = model
        self.posters = posters
        self.chooseFolder = chooseFolder
        self.copy = copy
        self.reveal = reveal
        self.close = close
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export").font(Theme.Font.display(18)).accessibilityAddTraits(.isHeader)
            plates
            if case .exporting(let progress) = model.state { progressBar(progress) }
            settings
            footer
        }
        .padding(24)
        .frame(width: Self.width)
        .foregroundStyle(Theme.ink.color)
        .background(Theme.sheet.color)
        .animation(reduceMotion ? nil : .easeOut(duration: Theme.Motion.saved), value: model.state)
    }

    static let width: CGFloat = 680
    static let plateGap: CGFloat = 12
    static let plateColumn: CGFloat = 76

    /// All five shapes side by side on one baseline, at one height that fits the sheet.
    private var plates: some View {
        let aspects = ShapePreset.allCases.map { shape -> Double in
            let size = shape.pixelSize(recording: model.editor.take.size)
            return Double(size.width) / Double(max(size.height, 1))
        }
        let room = Self.width - 48 - Self.plateGap * Double(aspects.count - 1)
        // Narrow plates keep a column wide enough for their size line, so shrink until all fit.
        var height = 120.0
        while height > 40, aspects.map({ max(height * $0, Self.plateColumn) }).reduce(0, +) > room { height -= 2 }
        return HStack(alignment: .bottom, spacing: Self.plateGap) {
            ForEach(Array(ShapePreset.allCases.enumerated()), id: \.element) { i, shape in
                plate(shape, size: CGSize(width: height * aspects[i], height: height))
            }
        }
        .disabled(isExporting)
    }

    private func plate(_ shape: ShapePreset, size: CGSize) -> some View {
        let checked = model.shapes.contains(shape)
        return Button { model.toggle(shape) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if let poster = posters[shape] { Image(decorative: poster, scale: 1).resizable() } else { Rectangle().fill(Theme.raised.color) }
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(checked ? Theme.ink.color : Theme.border.color,
                                                                        lineWidth: checked ? 2 : 1))
                .opacity(checked ? 1 : 0.6)
                HStack(spacing: 5) {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checked ? Theme.ink.color : Theme.muted.color)
                    Text(shape.label).font(Theme.Font.display(13))
                }
                Text(verbatim: model.sizeText(shape)).font(Theme.Font.tick).monospacedDigit().foregroundStyle(Theme.muted.color)
                    .lineLimit(1).fixedSize()
            }
            .frame(width: max(size.width, Self.plateColumn), alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(shape.label), \(model.sizeText(shape))")
        .accessibilityAddTraits(checked ? [.isSelected, .isButton] : .isButton)
    }

    private func progressBar(_ progress: Double) -> some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.active.color)
                    Capsule().fill(Theme.ink.color).frame(width: geo.size.width * progress)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 6)
            Text("\(Int((progress * 100).rounded()))%").font(Theme.Font.meta).monospacedDigit().foregroundStyle(Theme.muted.color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exporting")
        .accessibilityValue("\(Int((progress * 10).rounded() * 10)) percent")
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Frame rate").font(Theme.Font.bodyMedium)
                Spacer()
                if shot {
                    ShotControls.segmented(["60 fps", "30 fps"], selected: model.fps == 60 ? 0 : 1).frame(width: 180)
                } else {
                    Picker("Frame rate", selection: $model.fps) {
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
