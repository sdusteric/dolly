import AVFoundation
import CoreGraphics
import DollyCore
import Foundation
import Vision

/// Names a zoom from the pixels at its click (spec 4.6): on-device text recognition in a
/// 300 x 120 pt box around the click, and the line nearest the click wins. No Accessibility.
public struct ZoomNamer: ZoomNaming {
    public static let box = CGSize(width: 300, height: 120)

    public init() {}

    public func name(for click: Click, movie: URL, take: Take) async -> String {
        let fallback = "Click at \(TimeText.clock(click.t))"
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)
        guard let frame = try? await generator.image(at: CMTime(seconds: click.t, preferredTimescale: 600)).image else { return fallback }
        let scale = Double(frame.width) / max(take.size.width, 1)
        return await Self.text(near: click.point, in: frame, pixelScale: scale) ?? fallback
    }

    /// The recognized line nearest `point` (recording points) inside the box around it, or nil.
    public static func text(near point: CGPoint, in image: CGImage, pixelScale: Double) async -> String? {
        let w = Double(image.width), h = Double(image.height)
        let size = CGSize(width: min(box.width * pixelScale, w), height: min(box.height * pixelScale, h))
        let center = CGPoint(x: point.x * pixelScale, y: point.y * pixelScale)
        let crop = CGRect(x: min(max(center.x - size.width / 2, 0), w - size.width),
                          y: min(max(center.y - size.height / 2, 0), h - size.height),
                          width: size.width, height: size.height).integral
        guard let piece = image.cropping(to: crop) else { return nil }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        guard let lines = try? await request.perform(on: piece) else { return nil }
        let click = CGPoint(x: center.x - crop.minX, y: center.y - crop.minY)
        let best = lines.compactMap { line -> (String, Double)? in
            guard let text = line.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
            let b = line.boundingBox.cgRect
            let mid = CGPoint(x: b.midX * crop.width, y: (1 - b.midY) * crop.height)
            return (text, hypot(mid.x - click.x, mid.y - click.y))
        }.min { $0.1 < $1.1 }
        return best?.0
    }
}
