import AppKit
import DollyCore
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
        .environment(\.colorScheme, options.scheme)
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

/// The workspace each scenario shows. Stage, inspector and timeline are added in their tasks.
@MainActor
enum ShotWorkspace {
    static func view(editor: EditorModel, scenario: String, inputs: ShotScenarios.Inputs, scheme: ColorScheme) -> some View {
        EditorWorkspace(editor: editor, stage: AnyView(Color.clear), inspector: AnyView(Color.clear), timeline: AnyView(Color.clear))
    }
}
