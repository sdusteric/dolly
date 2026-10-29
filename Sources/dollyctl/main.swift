import AVFoundation
import CoreGraphics
import DollyCore
import DollyRender
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Headless tools on DollyCore and DollyRender. Never links ScreenCaptureKit or Sparkle, never
// writes outside the paths it is given.

let usage = """
usage:
  dollyctl zooms <pointer.csv|pointer.bin> --size WxH --target window|area|display
  dollyctl camera <take-folder> --at <seconds>
  dollyctl render <take-folder> --frames 0,8.6 --out <dir> [--shape original|16x9|1x1|4x5|9x16]
  dollyctl captions <take-folder> --srt
  dollyctl pointer <take-folder>
  dollyctl fixture shelf-demo --out <dir>
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

func option(_ name: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func loadTake(_ path: String) -> (Take, URL) {
    let folder = URL(filePath: path, directoryHint: .isDirectory)
    do {
        let data = try Data(contentsOf: folder.appending(path: TakeStore.jsonName))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try decoder.decode(Take.self, from: data), folder)
    } catch {
        fail("can't read take at \(path): \(error.localizedDescription)")
    }
}

func frame(of movie: URL, at t: Double) async -> CGImage? {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
    let tolerance = CMTime(value: 1, timescale: 60)
    generator.requestedTimeToleranceBefore = tolerance
    generator.requestedTimeToleranceAfter = tolerance
    return try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
}

func writePNG(_ image: CGImage, to url: URL) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { fail(usage) }
let rest = Array(args.dropFirst())

switch command {
case "zooms":
    guard let file = rest.first, let size = option("--size", in: rest).flatMap(DollyctlCommands.parseSize),
          let target = option("--target", in: rest).flatMap(TargetKind.init(rawValue:)) else { fail(usage) }
    let url = URL(filePath: file)
    let samples: [PointerSample]
    do {
        samples = url.pathExtension == "csv" ? try PointerLog.fromCSV(String(contentsOf: url, encoding: .utf8)) : try PointerLog.read(url)
    } catch {
        fail("can't read \(file): \(error.localizedDescription)")
    }
    DollyctlCommands.zoomLines(samples: samples, size: size, target: target).forEach { print($0) }

case "camera":
    guard let path = rest.first, let at = option("--at", in: rest).flatMap(Double.init) else { fail(usage) }
    let (take, folder) = loadTake(path)
    print(DollyctlCommands.cameraLine(take: take, pointer: TakeInputs.pointerPath(take: take, folder: folder), at: at))

case "render":
    guard let path = rest.first, let times = option("--frames", in: rest).flatMap(DollyctlCommands.parseTimes),
          let out = option("--out", in: rest) else { fail(usage) }
    let (take, folder) = loadTake(path)
    let outURL = URL(filePath: out, directoryHint: .isDirectory)
    do {
        try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)
    } catch {
        fail("can't create \(out)")
    }
    let shape: ShapePreset
    do {
        shape = try option("--shape", in: rest).map(DollyctlCommands.parseShape) ?? take.currentShape
    } catch {
        fail(error.localizedDescription)
    }
    let pointer = TakeInputs.pointerPath(take: take, folder: folder)
    let layout = ShapeLayout(shape: shape, recordingSize: take.size, padding: take.look.padding)
    let camera = CameraPath(zooms: take.zooms, layout: layout, pointer: pointer.map { p in { @Sendable t in p.position(at: t) } },
                            duration: take.duration)
    for t in times {
        var webcam: CGImage?
        if let track = take.camera { webcam = await frame(of: folder.appending(path: track.file), at: max(t - track.startOffset, 0)) }
        guard let recording = await frame(of: folder.appending(path: TakeStore.movieName), at: t),
              let image = StillRenderer.render(take: take, folder: folder, shape: shape, recording: recording, camera: camera.camera(at: t),
                                               pointer: pointer?.position(at: t).map { ($0, pointer?.shape(at: t) ?? .arrow) },
                                               ring: pointer?.ring(at: t).map { ($0.center, $0.progress) },
                                               cameraFrame: webcam, at: t, depthProgress: camera.depthProgress(at: t))
        else { fail("can't render \(t) s") }
        let url = outURL.appending(path: "frame-\(shape.fileSuffix)-\(String(format: "%.1f", t)).png")
        guard writePNG(image, to: url) else { fail("can't write \(url.path(percentEncoded: false))") }
        print("wrote \(url.path(percentEncoded: false)) (\(image.width)x\(image.height))")
    }

case "captions":
    guard let path = rest.first, rest.contains("--srt") else { fail(usage) }
    let (take, _) = loadTake(path)
    print(DollyctlCommands.captionsSRT(take), terminator: "")

case "pointer":
    guard let path = rest.first else { fail(usage) }
    let (_, folder) = loadTake(path)
    do {
        print(PointerLog.csv(try PointerLog.read(folder.appending(path: TakeStore.pointerName))), terminator: "")
    } catch {
        fail("can't read the pointer log: \(error.localizedDescription)")
    }

case "fixture":
    guard rest.first == "shelf-demo", let out = option("--out", in: rest) else { fail(usage) }
    // A take folder laid out like DOLLY_HOME (Movies/Takes/<id>/) plus the CSV of Task 3.
    let root = URL(filePath: out, directoryHint: .isDirectory)
    let store = TakeStore(paths: DollyPaths(environment: ["DOLLY_HOME": root.path(percentEncoded: false)]))
    let samples = SyntheticTake.shelfDemoSamples()
    var take = SyntheticTake.shelfDemo()
    take.pixelScale = 1
    take.fps = 30
    do {
        let folder = try store.createFolder(for: take.id)
        try PointerLog.csv(samples).write(to: root.appending(path: "shelf-demo.csv"), atomically: true, encoding: .utf8)
        let pointer = try PointerLogWriter(url: folder.appending(path: TakeStore.pointerName))
        samples.forEach(pointer.append)
        try pointer.close()
        let window = try WindowFrameLogWriter(url: folder.appending(path: TakeStore.windowName))
        window.append(WindowFrameSample(t: 0, frame: CGRect(origin: .zero, size: take.size)))
        try window.close()
        let clicks = ClickDetector.clicks(from: samples, geometry: take.geometry(windowFrames: [WindowFrameSample(t: 0, frame: CGRect(origin: .zero, size: take.size))]),
                                          recordingStartHost: 0, stopRequestHost: take.duration)
        take.zooms = ZoomRules().zooms(for: clicks, size: take.size, target: .window, trim: take.trim)
        try await SyntheticTake.writeMovie(seconds: take.duration, fps: take.fps, variableRate: false, size: take.size,
                                           to: folder.appending(path: TakeStore.movieName))
        try store.save(take)
        print("wrote \(root.appending(path: "shelf-demo.csv").path(percentEncoded: false))")
        print("wrote \(folder.path(percentEncoded: false)) (\(take.zooms.count) zooms)")
    } catch {
        fail("fixture failed: \(error.localizedDescription)")
    }

default:
    fail(usage)
}
