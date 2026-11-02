import CoreGraphics
import DollyCore
import DollyUI
import Foundation
import ImageIO
import SwiftUI

/// Demo content for shot mode, built from the fixtures folder shots.sh fills: the Shelf demo
/// pointer log and the Shelf panel screenshot as the recording's frame.
@MainActor
enum ShotScenarios {
    struct Inputs {
        let samples: [PointerSample]
        let footage: CGImage?
    }

    static func inputs(fixtures: URL, scheme: ColorScheme) -> Inputs {
        let csv = (try? String(contentsOf: fixtures.appending(path: "shelf-demo.csv"), encoding: .utf8)) ?? ""
        let samples = (try? PointerLog.fromCSV(csv)) ?? []
        let png = fixtures.appending(path: scheme == .dark ? "footage-dark.png" : "footage-light.png")
        let footage = CGImageSourceCreateWithURL(png as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        return Inputs(samples: samples, footage: footage)
    }

    /// The webcam in shots: one solid warm color, standing in for a face.
    static let cameraFrame: CGImage? = {
        let ctx = CGContext(data: nil, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.setFillColor(CGColor(srgbRed: 0.78, green: 0.62, blue: 0.48, alpha: 1))
        ctx?.fill(CGRect(x: 0, y: 0, width: 64, height: 36))
        return ctx?.makeImage()
    }()

    /// The export sheet's plates: the play still in every shape.
    static func plates(_ editor: EditorModel, footage: CGImage?) -> [ShapePreset: CGImage] {
        guard let footage else { return [:] }
        var out: [ShapePreset: CGImage] = [:]
        for shape in ShapePreset.allCases { out[shape] = ShotWorkspace.playStill(editor, footage, shape: shape) }
        return out
    }

    /// The studio mockups (docs/mockup/studio): shape, backdrop, playhead and what is selected.
    static func studio(_ scenario: String, _ editor: EditorModel) {
        editor.select(nil)
        switch scenario {
        case "studio-look":
            editor.setShape(.portrait4x5)
            editor.setBackdrop(.gradient(id: "rose"))
            editor.playhead = 24.6
        case "studio-zoom":
            editor.setBackdrop(.gradient(id: "harbor"))
            if editor.take.zooms.count > 1 { editor.select(editor.take.zooms[1].id) }
            editor.playhead = 8.6
        case "studio-camera":
            editor.setBackdrop(.gradient(id: "slate"))
            editor.playhead = 12.4
            editor.selectCamera()
        case "studio-captions":
            editor.setShape(.tall9x16)
            editor.setBackdrop(.gradient(id: "moss"))
            editor.setCamera { $0.corner = .topLeft }
            editor.playhead = 12.4
            if let fourth = editor.take.captions?.items.dropFirst(3).first { editor.selectCaption(fourth.id) }
        default:
            break
        }
    }

    /// The take of the mockups: recorded today at 10:42, zoom 2 selected, playhead at 0:08.6.
    static func shelfEditor(_ inputs: Inputs) -> EditorModel {
        let geometry = RecordingGeometry(target: .window, recordingRect: .zero,
                                         windowFrames: [WindowFrameSample(t: 0, frame: CGRect(x: 0, y: 0, width: 848, height: 858))],
                                         size: CGSize(width: 848, height: 858))
        let clicks = ClickDetector.clicks(from: inputs.samples, geometry: geometry, recordingStartHost: 0, stopRequestHost: 48.2)
        var take = SyntheticTake.shelfDemo()
        take.created = Calendar.current.date(bySettingHour: 10, minute: 42, second: 0, of: Date()) ?? Date()
        take.zooms = ZoomRules().zooms(for: clicks, size: take.size, target: .window, trim: take.trim)
        // What ZoomNamer reads off the footage next to each zoom's first click.
        for (i, name) in ["Haul", "Run check up", "Update", "Capture area", "New episode"].enumerated() where i < take.zooms.count {
            take.zooms[i].name = name
        }
        take.camera = CameraTrack(startOffset: 0)
        take.camera?.hidden = [33.0...36.5]
        take.captions = SyntheticTake.shelfCaptions()
        take.microphoneOffset = 0
        let pointer = PointerPath(samples: inputs.samples, geometry: geometry, clicks: clicks, recordingStartHost: 0, look: take.look)
        let editor = EditorModel(take: take, pointer: pointer)
        if take.zooms.count > 1 { editor.select(take.zooms[1].id) }
        editor.playhead = 8.6
        return editor
    }

    static func sidebarEntries(_ shelf: Take) -> [TakeEntry] {
        let folder = URL(filePath: "/tmp/dolly-shot", directoryHint: .isDirectory)
        var take1 = Take(name: "Shelf Tile Board, take 1", target: .window, size: CGSize(width: 848, height: 858),
                         pixelScale: 2, fps: 60, duration: 72.6)
        take1.zooms = (0..<7).map { i in
            Zoom(start: Double(i * 9), end: Double(i * 9 + 3), aim: .zero, depth: 1.6, mode: .hold, moveIn: 0.6,
                 moveOut: 0.5, source: .auto, clickIDs: [i], name: "")
        }
        var snapTake = Take(name: "Snap all-in-one toolbar", target: .window, size: CGSize(width: 900, height: 120), pixelScale: 2, fps: 60, duration: 36.0)
        snapTake.exports = [ExportRecord(shape: .wide16x9, url: folder, date: Date())]
        var tidy = Take(name: "Tidy check up", target: .window, size: CGSize(width: 980, height: 700), pixelScale: 2, fps: 60, duration: 52.4)
        tidy.exports = [ExportRecord(shape: .wide16x9, url: folder, date: Date())]
        return [shelf, take1, snapTake, tidy].map { .ok($0, folder: folder.appending(path: $0.id.uuidString)) }
    }

    static func model(_ scenario: String, inputs: Inputs) -> EditorScreenModel {
        let shortcut = HotkeyCombo.defaultRecord.displayString
        guard scenario != "editor-empty" else {
            return EditorScreenModel(entries: [], totalBytes: 0, editor: nil, recordShortcut: shortcut)
        }
        let editor = shelfEditor(inputs)
        if scenario.hasPrefix("studio-") { studio(scenario, editor) }
        let model = EditorScreenModel(entries: sidebarEntries(editor.take), totalBytes: 1_900_000_000, editor: editor,
                                      recordShortcut: shortcut)
        if scenario == "editor-rename" { model.renaming = model.entries.dropFirst().first?.folder }
        if let footage = inputs.footage {
            let image = Image(decorative: footage, scale: 1)
            for entry in model.entries.prefix(2) {
                if case .ok(let take, _) = entry { model.posters[take.id] = image }
            }
        }
        return model
    }
}
