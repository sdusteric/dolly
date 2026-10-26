import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A take's sidebar picture: one frame as a 480 px wide JPEG.
public enum PosterMaker {
    public static let width = 480

    public static func poster(movie: URL, at t: Double, to url: URL) async throws {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
        generator.maximumSize = CGSize(width: width, height: width * 4)
        let image = try await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
