import AppKit
import DollyCore
import DollyRender
import DollyUI
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// `Dolly --shot <scenario> --appearance light|dark --size WxH --out <png> --fixtures <dir>`.
/// Renders the editor with `ImageRenderer` at 2x and exits. It never calls `NSApplication.run`,
/// never creates a window and never touches `NSApp`, so the frontmost app cannot change (Reel's
/// pattern). `DOLLY_HOME` must be set.
enum ShotMode {
    struct Options {
        var scenario = "editor"
        var scheme = ColorScheme.light
        var size = CGSize(width: 1440, height: 900)
        var out = URL(filePath: "shot.png")
        var fixtures = URL(filePath: ".", directoryHint: .isDirectory)
    }

    static func parse(_ arguments: [String]) -> Options? {
        var o = Options()
        var i = 0
        while i < arguments.count {
            let value = i + 1 < arguments.count ? arguments[i + 1] : ""
            switch arguments[i] {
            case "--shot": o.scenario = value
            case "--appearance": o.scheme = value == "dark" ? .dark : .light
            case "--size":
                let parts = value.split(separator: "x").compactMap { Double($0) }
                guard parts.count == 2 else { return nil }
                o.size = CGSize(width: parts[0], height: parts[1])
            case "--out": o.out = URL(filePath: value)
            case "--fixtures": o.fixtures = URL(filePath: value, directoryHint: .isDirectory)
            default: return nil
            }
            i += 2
        }
        return o
    }

    static func run(_ arguments: [String]) -> Never {
        guard ProcessInfo.processInfo.environment["DOLLY_HOME"] != nil, let options = parse(arguments) else {
            FileHandle.standardError.write(Data("Dolly --shot needs DOLLY_HOME and valid arguments\n".utf8))
            exit(64)
        }
        Task { @MainActor in exit(render(options)) }
        while true { RunLoop.main.run(mode: .default, before: .distantFuture) }
    }

    @MainActor
    static func render(_ options: Options) -> Int32 {
        let inputs = ShotScenarios.inputs(fixtures: options.fixtures, scheme: options.scheme)
        let model = ShotScenarios.model(options.scenario, inputs: inputs)
        let view = EditorView(model: model, showsWindowControls: true) { editor in
            AnyView(ShotWorkspace.view(editor: editor, scenario: options.scenario, inputs: inputs, scheme: options.scheme))
        }
        .frame(width: options.size.width, height: options.size.height)
        .overlay(alignment: .top) { ShotOverlays.view(options.scenario, editor: model.editor, footage: inputs.footage) }
        .environment(\.colorScheme, options.scheme)
        .environment(\.dollyShot, true)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        var image: CGImage?
        NSAppearance(named: options.scheme == .dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            image = renderer.cgImage
        }
        guard let image,
              let destination = CGImageDestinationCreateWithURL(options.out as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            FileHandle.standardError.write(Data("ImageRenderer produced no image\n".utf8))
            return 1
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return 1 }
        print("wrote \(options.out.path(percentEncoded: false)) (\(image.width)x\(image.height))")
        return 0
    }
}

/// The workspace each scenario shows: the stage from the Shelf footage through Dolly's own frame
/// composer; inspector and timeline are added in their tasks.
@MainActor
enum ShotWorkspace {
    static func view(editor: EditorModel, scenario: String, inputs: ShotScenarios.Inputs, scheme: ColorScheme) -> some View {
        if scenario == "stage-play" { editor.select(nil) }
        let clicks = editor.pointer?.clicks ?? []
        return EditorWorkspace(editor: editor,
                               stage: AnyView(StageView(editor: editor, image: still(editor, inputs), player: nil, isPlaying: false, clicks: clicks)),
                               inspector: AnyView(InspectorView(editor: editor, clicks: clicks, useForNewTakes: { _ in })),
                               timeline: AnyView(TimelineView(editor: editor, clickTimes: clicks.map(\.t),
                                                              filmstrip: inputs.footage.map { Image(decorative: $0, scale: 1) },
                                                              playback: nil, isPlaying: false)))
    }

    /// Aim mode shows the recording at 1x; play mode the output at the playhead with its pointer.
    static func still(_ editor: EditorModel, _ inputs: ShotScenarios.Inputs) -> CGImage? {
        guard let footage = inputs.footage else { return nil }
        if editor.selectedZoom != nil { return StillRenderer.render(take: editor.take, recording: footage, camera: nil, pointer: nil, ring: nil) }
        return playStill(editor, footage)
    }

    static func playStill(_ editor: EditorModel, _ footage: CGImage) -> CGImage? {
        let take = editor.take
        let layout = ShapeLayout(shape: .wide16x9, recordingSize: take.size, padding: take.look.padding)
        let pointer = editor.pointer
        let path = CameraPath(zooms: take.zooms, layout: layout, pointer: pointer.map { p in { @Sendable t in p.position(at: t) } },
                              duration: take.duration)
        let t = editor.playhead
        return StillRenderer.render(take: take, recording: footage, camera: path.camera(at: t),
                                    pointer: pointer?.position(at: t).map { ($0, pointer?.shape(at: t) ?? .arrow) },
                                    ring: pointer?.ring(at: t).map { ($0.center, $0.progress) })
    }
}

/// Panels that float over the editor in the recording scenarios.
@MainActor
enum ShotOverlays {
    /// Shot mode never exports; this only satisfies the sheet's model.
    struct NoExporter: ExportRunning {
        func export(_ plan: ExportPlan, takeFolder: URL, pointer: PointerPath?,
                    progress: @escaping @Sendable (Double) -> Void) async throws -> URL { throw CancellationError() }
    }

    @ViewBuilder static func view(_ scenario: String, editor: EditorModel?, footage: CGImage?) -> some View {
        switch scenario {
        case "export", "export-progress", "export-done":
            if let editor {
                let sheet = ExportSheetModel(editor: editor, takeFolder: URL(filePath: "/tmp"),
                                             folder: URL(filePath: NSHomeDirectory() + "/Movies/Dolly"), exporter: NoExporter())
                let _ = sheet.state = scenario == "export-progress" ? .exporting(progress: 0.62)
                    : scenario == "export-done" ? .done([URL(filePath: "/x/Shelf Tile Board demo 16x9.mp4")]) : .ready
                ZStack(alignment: .top) {
                    Color.black.opacity(0.25)
                    ExportSheet(model: sheet, poster: footage.flatMap { ShotWorkspace.playStill(editor, $0) }, chooseFolder: {},
                                copy: { _ in }, reveal: { _ in }, close: {})
                        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
                        .compositingGroup().shadow(color: .black.opacity(0.25), radius: 24, y: 8)
                        .padding(.top, 52)
                }
            }
        case "record-bar":
            var model = RecordBarModel()
            let _ = model.windowID = 7
            ZStack(alignment: .top) {
                // The tape around the chosen window, here the editor's stage.
                WindowHighlightView().frame(width: 1000, height: 600).padding(.top, 150)
                RecordBar(model: .constant(model), windows: [PickableWindow(id: 7, app: "Safari", title: "sdusteric.dev",
                                                                           frame: .zero, displayID: 1)],
                          shortcut: HotkeyCombo.defaultRecord.displayString, record: {}, cancel: {})
                    .padding(.top, 24)
            }
        case "take-card":
            ZStack(alignment: .bottomTrailing) {
                Color.black.opacity(0.25)
                TakeCardView(model: TakeCardModel(name: editor?.take.name ?? "Take", duration: editor?.take.duration ?? 48,
                                                  zooms: editor?.take.zooms.count ?? 5, size: editor?.take.size ?? CGSize(width: 16, height: 9)),
                             poster: footage.map { Image(decorative: $0, scale: 1) }, edit: {}, export: {}, close: {})
                    .padding(TakeCardModel.edgeInset)
            }
        case "countdown":
            CountdownView(number: 2).frame(maxWidth: .infinity, maxHeight: .infinity)
        case "settings":
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let model = SettingsScreenModel(settings: DollyCore.Settings(), showsAdvanced: true, takesFolder: "~/Movies/Dolly/Takes",
                                            defaultClipsFolder: NSHomeDirectory() + "/Movies/Dolly")
            let _ = model.lastClick = (CGPoint(x: 512, y: 300), now.addingTimeInterval(-0.4))
            ZStack {
                Color.black.opacity(0.25)
                SettingsView(model: model, now: now)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .compositingGroup().shadow(color: .black.opacity(0.25), radius: 24, y: 8)
            }
        case "permission":
            ZStack {
                Color.black.opacity(0.25)
                PermissionWindowView(denied: false, allow: {}, openSettings: {})
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .compositingGroup().shadow(color: .black.opacity(0.25), radius: 24, y: 8)
            }
        default:
            EmptyView()
        }
    }
}
