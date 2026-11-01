import AVFoundation
import CoreImage
import CoreGraphics
import Foundation
import Testing
@testable import DollyCore
@testable import DollyRender

@Suite struct CompositorTests {
    func fixture() async throws -> (Take, URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "dolly-comp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await SyntheticTake.writeMovie(seconds: 3, fps: 60, variableRate: true, to: folder.appending(path: TakeStore.movieName))
        let take = Take(name: "Fixture", target: .display, size: CGSize(width: 1440, height: 900), pixelScale: 1, fps: 60, duration: 3)
        return (take, folder)
    }

    @Test func syntheticMovieIsVariableRate() async throws {
        let (_, folder) = try await fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let asset = AVURLAsset(url: folder.appending(path: TakeStore.movieName))
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let provider = reader.outputProvider(for: AVAssetReaderTrackOutput(track: track, outputSettings: nil))
        try reader.start()
        var frames = 0
        while let sample = try await provider.next() { frames += sample.sampleCount }
        #expect(frames > 100 && frames < 150)   // 3 s at 60 fps minus the still second
    }

    @Test func compositorRendersAThreeSecondFixture() async throws {
        let (take, folder) = try await fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (asset, composition) = try await PlayerItemFactory.composition(take: take, folder: folder, shape: .wide16x9, fps: 60, pointer: nil)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.videoComposition = composition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: 1.5, preferredTimescale: 600)).image
        #expect(image.width == 1920 && image.height == 1080)
        // The compositor must not change colors: its center matches a plain decode of the same frame.
        let plain = AVAssetImageGenerator(asset: AVURLAsset(url: folder.appending(path: TakeStore.movieName)))
        let source = pixel(CIImage(cgImage: try await plain.image(at: CMTime(seconds: 0.9, preferredTimescale: 600)).image), 720, 450)
        let out = pixel(CIImage(cgImage: image), 960, 540)
        #expect(abs(out.r - source.r) <= 4 && abs(out.g - source.g) <= 4 && abs(out.b - source.b) <= 4)
        #expect(near(pixel(CIImage(cgImage: image), 10, 10), 0x3E4A4F, tol: 4))   // the background
    }

    /// The editor's preview renders at twice the canvas on a Retina screen, so a zoom shows the
    /// recording's own pixels instead of a stretched 1080p frame. Same picture, more pixels.
    @Test func previewRendersAtTwiceTheCanvas() async throws {
        let (take, folder) = try await fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (asset, composition) = try await PlayerItemFactory.composition(take: take, folder: folder, shape: .wide16x9, fps: 60,
                                                                           pointer: nil, renderScale: 2)
        #expect(composition.renderSize == CGSize(width: 3840, height: 2160))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.videoComposition = composition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = CIImage(cgImage: try await generator.image(at: CMTime(seconds: 1.5, preferredTimescale: 600)).image)
        #expect(image.extent.size == CGSize(width: 3840, height: 2160))
        #expect(near(pixel(image, 20, 20), 0x3E4A4F, tol: 4))
        // The recording's top-left corner sits where the 1x canvas puts it, doubled.
        let layout = ShapeLayout(shape: .wide16x9, recordingSize: take.size, padding: take.look.padding)
        let inside = CGPoint(x: (layout.recordingRect.minX + 40) * 2, y: (layout.recordingRect.minY + 40) * 2)
        #expect(!near(pixel(image, Int(inside.x), Int(inside.y)), 0x3E4A4F, tol: 4))
    }

    @Test func compositionHonorsTrim() async throws {
        var (take, folder) = try await fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        take.trim = 0.5...2.5
        let (asset, composition) = try await PlayerItemFactory.composition(take: take, folder: folder, shape: .wide16x9, fps: 30, pointer: nil)
        #expect(approx(try await asset.load(.duration).seconds, 2.0, tol: 0.02))
        #expect(composition.frameDuration == CMTime(value: 1, timescale: 30))
    }
}

func approx(_ a: Double, _ b: Double, tol: Double) -> Bool { abs(a - b) <= tol }
