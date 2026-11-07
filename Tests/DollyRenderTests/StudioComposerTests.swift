import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import DollyCore
@testable import DollyRender

/// Every pixel of `image` as RGBA8, top row first.
func bitmap(_ image: CIImage) -> [UInt8] {
    let w = Int(image.extent.width), h = Int(image.extent.height)
    var px = [UInt8](repeating: 0, count: w * h * 4)
    testContext.render(image, toBitmap: &px, rowBytes: w * 4, bounds: image.extent, format: .RGBA8,
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    return px
}

@Suite struct StudioComposerTests {
    let size = CGSize(width: 1440, height: 900)
    var layout: ShapeLayout { ShapeLayout(shape: .wide16x9, recordingSize: size, padding: 64) }
    var recording: CIImage { redRecording(size: size, square: CGPoint(x: 636, y: 318)) }

    func compose(_ look: Look, picture: CIImage? = nil, cameraFrame: CIImage? = nil, camera: CameraTrack? = nil,
                 depthProgress: Double = 0, caption: String? = nil) -> CIImage {
        FrameComposer(layout: layout, look: look, recordingPixelScale: 1, backdropImage: picture)
            .compose(recording: recording, camera: layout.rest, pointer: nil, ring: nil, cameraFrame: cameraFrame,
                     cameraState: camera.map { ($0, depthProgress) }, caption: caption)
    }

    func brightness(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Int { p.r + p.g + p.b }

    @Test func gradientBackdropIsLighterAtItsLight() {
        var look = Look()
        look.background = .gradient(id: "rose")
        let out = compose(look)
        #expect(brightness(pixel(out, 480, 8)) > brightness(pixel(out, 1910, 1072)) + 150)
    }

    @Test func pictureBackdropFillsAndBlurs() {
        let half = CGRect(x: 0, y: 0, width: 200, height: 300)
        let picture = CIImage(color: .white).cropped(to: half.offsetBy(dx: 200, dy: 0))
            .composited(over: CIImage(color: .black).cropped(to: half))
        var look = Look()
        look.background = .picture(file: "backdrop.png", blur: 0)
        let sharp = compose(look, picture: picture)
        #expect(near(pixel(sharp, 940, 20), 0x000000) && near(pixel(sharp, 980, 20), 0xFFFFFF))
        #expect(near(pixel(sharp, 2, 2), 0x000000) && near(pixel(sharp, 1917, 2), 0xFFFFFF))   // filled to the edges
        look.background = .picture(file: "backdrop.png", blur: 40)
        let soft = pixel(compose(look, picture: picture), 950, 20)
        #expect(soft.r > 40 && soft.r < 215)
        #expect(near(pixel(compose(look, picture: picture), 2, 540), 0x000000, tol: 8))   // no dark fringe from the blur at the edge
    }

    @Test func shadowZeroDrawsNoShadow() {
        var look = Look()
        look.shadow = 0
        #expect(near(pixel(compose(look), 960, 1030), 0x3E4A4F))
        look.shadow = 1
        #expect(brightness(pixel(compose(look), 960, 1030)) < brightness(pixel(compose(Look()), 960, 1030)))
    }

    @Test func missingPictureRendersDefaultColor() {
        var look = Look()
        look.background = .picture(file: "backdrop.jpg", blur: 10)
        #expect(near(pixel(compose(look), 10, 10), 0x3E4A4F))
    }

    @Test func cameraBubbleShowsCameraPixels() throws {
        // A red camera frame with a green stripe left of center (camera x 300...400 of 1280).
        let frame = CIImage(color: CIColor(red: 0, green: 1, blue: 0)).cropped(to: CGRect(x: 300, y: 0, width: 100, height: 720))
            .composited(over: CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 720)))
        var camera = CameraTrack(startOffset: 0)
        let o = OverlayLayout(canvas: layout.canvas, recordingRect: layout.recordingRect, padding: 64, camera: camera,
                              captionPosition: .bottom, captionHeight: 0)
        let b = try #require(o.bubble(at: 0))
        let mirrored = compose(Look(), cameraFrame: frame, camera: camera)
        #expect(near(pixel(mirrored, Int(b.midX), Int(b.midY)), 0xFF0000, tol: 8))
        #expect(near(pixel(mirrored, Int(b.maxX - 30), Int(b.midY)), 0x00FF00, tol: 8))
        #expect(near(pixel(mirrored, Int(b.minX + 30), Int(b.midY)), 0xFF0000, tol: 8))
        #expect(near(pixel(mirrored, Int(b.minX) + 1, Int(b.midY)), 0xFFFFFF, tol: 12))   // the 3 pt border
        camera.mirror = false
        let plain = compose(Look(), cameraFrame: frame, camera: camera)
        #expect(near(pixel(plain, Int(b.minX + 30), Int(b.midY)), 0x00FF00, tol: 8))
        #expect(near(pixel(compose(Look(), cameraFrame: frame, camera: nil), Int(b.midX), Int(b.midY)), 0x3E4A4F))
    }

    @Test func captionDrawsInsideItsRect() throws {
        let text = "Each tile has its own quick actions."
        let composer = FrameComposer(layout: layout, look: Look(), recordingPixelScale: 1)
        let rect = try #require(composer.captionRect(text, camera: nil))
        #expect(rect.width > 200 && rect.height > 20 && rect.maxY <= layout.canvas.height)
        let with = bitmap(compose(Look(), caption: text)), without = bitmap(compose(Look()))
        let w = Int(layout.canvas.width)
        var inside = 0, outside = 0
        for y in stride(from: 0, to: Int(layout.canvas.height), by: 3) {
            for x in stride(from: 0, to: w, by: 3) where with[(y * w + x) * 4] != without[(y * w + x) * 4] {
                if rect.insetBy(dx: -1, dy: -1).contains(CGPoint(x: x, y: y)) { inside += 1 } else { outside += 1 }
            }
        }
        #expect(inside > 100 && outside == 0)
    }

    @Test func captionArtWrapsLongTextToTwoLines() throws {
        let one = try #require(CaptionArt.image(text: "Short.", sizePoints: 15, k: 1, maxWidth: 1800))
        let two = try #require(CaptionArt.image(text: "This caption is long enough that it needs a second line to fit.",
                                                sizePoints: 15, k: 1, maxWidth: 1800))
        #expect(two.extent.height > one.extent.height * 1.5)
    }
}

@Suite struct StudioExportTests {
    @Test func exportWithCameraAndAudioHasBothTracks() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "dolly-studio-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "take"), out = root.appending(path: "out")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await SyntheticTake.writeMovie(seconds: 3, fps: 60, variableRate: false, to: folder.appending(path: TakeStore.movieName))
        try await SyntheticTake.writeCamera(to: folder.appending(path: "camera.mov"), seconds: 3, color: (220, 40, 40))
        try SyntheticTake.writeTone(to: folder.appending(path: TakeStore.audioName), seconds: 3)
        var take = Take(name: "Studio", target: .display, size: CGSize(width: 1440, height: 900), pixelScale: 1, fps: 60, duration: 3)
        take.camera = CameraTrack(startOffset: 0.25)
        take.microphoneOffset = 0
        let url = try await Exporter().export(ExportPlan(take: take, shape: .tall9x16, fps: 30, folder: out), takeFolder: folder,
                                              pointer: nil, progress: { _ in })
        let p = await VideoProbe.probe(url)
        #expect(p.videoTrackCount == 1 && p.audioTrackCount == 1)
        #expect(p.pixelSize == PixelSize(width: 1080, height: 1920))
        #expect(abs(p.durationSeconds - 3.0) <= 1.0 / 30 + 0.03)
    }

    /// Review finding 1: side tracks inserted from rounded times can run past the trimmed video,
    /// and AVAssetReader then refuses the composition.
    @Test func trimmedExportWithSideFilesSucceeds() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "dolly-trim-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "take"), out = root.appending(path: "out")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await SyntheticTake.writeMovie(seconds: 3, fps: 60, variableRate: false, to: folder.appending(path: TakeStore.movieName))
        try await SyntheticTake.writeCamera(to: folder.appending(path: "camera.mov"), seconds: 3, color: (220, 40, 40))
        try SyntheticTake.writeTone(to: folder.appending(path: TakeStore.audioName), seconds: 3)
        for (trim, cameraOffset, micOffset) in [(0.3337...2.7071, 0.1371, 0.0731), (0.9113...2.2229, 0.0123, 0.4567), (0.25...2.9, 0.1, -0.05)] {
            var take = Take(name: "Trim", target: .display, size: CGSize(width: 1440, height: 900), pixelScale: 1, fps: 60, duration: 3)
            take.trim = trim
            take.camera = CameraTrack(startOffset: cameraOffset)
            take.microphoneOffset = micOffset
            let url = try await Exporter().export(ExportPlan(take: take, shape: .wide16x9, fps: 30, folder: out), takeFolder: folder,
                                                  pointer: nil, progress: { _ in })
            let p = await VideoProbe.probe(url)
            #expect(p.audioTrackCount == 1 && abs(p.durationSeconds - (trim.upperBound - trim.lowerBound)) <= 1.0 / 30 + 0.03)
        }
    }

    /// Cuts and speed-ups shorten the clip; the sound keeps playing outside the sped-up part.
    @Test func cutsAndSpeedUpsShortenTheExport() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "dolly-speed-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "take"), out = root.appending(path: "out")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await SyntheticTake.writeMovie(seconds: 4, fps: 60, variableRate: true, to: folder.appending(path: TakeStore.movieName))
        try await SyntheticTake.writeCamera(to: folder.appending(path: "camera.mov"), seconds: 4, color: (220, 40, 40))
        try SyntheticTake.writeTone(to: folder.appending(path: TakeStore.audioName), seconds: 4)
        let cases: [([SpeedRegion], Double)] = [
            ([SpeedRegion(start: 1, end: 2, speed: .cut)], 3),
            ([SpeedRegion(start: 0.5, end: 2.5, speed: .fast(4))], 2.5),
            ([SpeedRegion(start: 0.2, end: 0.9, speed: .cut), SpeedRegion(start: 1.3337, end: 3.4071, speed: .fast(8))], 4 - 0.7 - 2.0734 * 7 / 8),
        ]
        for (regions, expected) in cases {
            var take = Take(name: "Speed", target: .display, size: CGSize(width: 1440, height: 900), pixelScale: 1, fps: 60, duration: 4)
            take.camera = CameraTrack(startOffset: 0.137)
            take.microphoneOffset = 0.0731
            take.speedRegions = regions
            #expect(abs(take.outputDuration - expected) < 0.001)
            let url = try await Exporter().export(ExportPlan(take: take, shape: .wide16x9, fps: 30, folder: out), takeFolder: folder,
                                                  pointer: nil, progress: { _ in })
            let p = await VideoProbe.probe(url)
            #expect(p.videoTrackCount == 1 && p.audioTrackCount == 1)
            #expect(abs(p.durationSeconds - expected) <= 1.0 / 30 + 0.03, "\(regions.map(\.speed))")
        }
    }

    /// System audio plays with the microphone, or alone; both mix into the one audio track.
    @Test func systemAudioIsMixedIntoTheExport() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "dolly-system-audio-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "take"), out = root.appending(path: "out")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await SyntheticTake.writeMovie(seconds: 3, fps: 60, variableRate: false, to: folder.appending(path: TakeStore.movieName))
        try SyntheticTake.writeTone(to: folder.appending(path: TakeStore.systemAudioName), seconds: 3)
        try SyntheticTake.writeTone(to: folder.appending(path: TakeStore.audioName), seconds: 3)
        for mic in [false, true] {
            var take = Take(name: "Sound", target: .display, size: CGSize(width: 1440, height: 900), pixelScale: 1, fps: 60, duration: 3)
            take.systemAudioOffset = 0.0213
            take.microphoneOffset = mic ? 0.05 : nil
            take.speedRegions = [SpeedRegion(start: 1, end: 1.5, speed: .cut)]
            let built = try await PlayerItemFactory.asset(take: take, folder: folder)
            #expect(try await built.asset.loadTracks(withMediaType: .audio).count == (mic ? 2 : 1))
            let url = try await Exporter().export(ExportPlan(take: take, shape: .wide16x9, fps: 30, folder: out), takeFolder: folder,
                                                  pointer: nil, progress: { _ in })
            let p = await VideoProbe.probe(url)
            #expect(p.audioTrackCount == 1 && abs(p.durationSeconds - 2.5) <= 1.0 / 30 + 0.03)
        }
    }
}
