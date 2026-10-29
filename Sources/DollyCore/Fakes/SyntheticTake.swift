import CoreGraphics
import Foundation

/// Demo takes for tests, shots and dollyctl.
public enum SyntheticTake {
    /// The Shelf Tile Board demo of the mockups: an 848 x 858 pt window, 48.2 s at 60 fps.
    public static func shelfDemo() -> Take {
        Take(
            name: "Shelf Tile Board demo",
            created: Date(timeIntervalSince1970: 1_793_011_320),
            target: .window,
            size: CGSize(width: 848, height: 858),
            pixelScale: 2,
            fps: 60,
            duration: 48.2
        )
    }

    /// The ten captions of the studio mockups, as if transcribed from the Shelf demo's voice.
    public static func shelfCaptions() -> CaptionTrack {
        let lines: [(Double, Double, String)] = [
            (0.4, 3.8, "This is Shelf, my launcher for every app."), (4.2, 7.2, "Haul shows what is downloading."),
            (7.6, 11.0, "Run check up tells Tidy to scan again."), (11.4, 14.6, "Each tile has its own quick actions."),
            (15.0, 20.8, "Updates install right from the board."), (21.2, 26.6, "Reel picks up where I left off."),
            (27.0, 31.8, "Snap keeps my last three captures."), (32.2, 37.6, "Booth knows which episode is next."),
            (38.0, 44.2, "Press a number to jump to any app."), (44.6, 47.8, "That is the whole board."),
        ]
        return CaptionTrack(source: .voice, locale: "en_US", items: lines.enumerated().map { i, l in
            Caption(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", i + 1)) ?? UUID(), start: l.0, end: l.1, text: l.2)
        })
    }

    /// The nine left clicks of the Shelf demo, in recording points (plan Task 3).
    public static let shelfDemoClicks: [(t: Double, x: Double, y: Double)] = [
        (2.4, 360, 225), (7.9, 636, 318), (15.2, 605, 280), (17.0, 560, 300), (19.8, 600, 283),
        (27.6, 383, 619), (29.9, 420, 619), (38.9, 715, 747), (41.2, 700, 747),
    ]

    /// The Shelf demo pointer log (`Fixtures/shelf-demo.csv`): 120 Hz for 48.2 s in a window at
    /// global (0, 0, 848, 858). The pointer rests 0.3 s either side of each click, moves in straight
    /// lines between them, and each press lasts 0.09 s.
    public static func shelfDemoSamples() -> [PointerSample] {
        let height = 858.0
        let rest = 0.3, press = 0.09
        // (leave time, point) then (arrive time, point) for each leg.
        var legs: [(t0: Double, p0: CGPoint, t1: Double, p1: CGPoint)] = []
        var leave = (t: rest, p: CGPoint(x: 424, y: 429))
        for click in shelfDemoClicks {
            let p = CGPoint(x: click.x, y: height - click.y)
            legs.append((leave.t, leave.p, click.t - rest, p))
            leave = (click.t + rest, p)
        }
        func position(_ t: Double) -> CGPoint {
            guard let first = legs.first, t > first.t0 else { return legs.first?.p0 ?? .zero }
            for leg in legs where t <= leg.t1 {
                if t <= leg.t0 { return leg.p0 }
                let f = (t - leg.t0) / (leg.t1 - leg.t0)
                return CGPoint(x: leg.p0.x + (leg.p1.x - leg.p0.x) * f, y: leg.p0.y + (leg.p1.y - leg.p0.y) * f)
            }
            return leave.p
        }
        let round2 = { (v: Double) in Float((v * 100).rounded() / 100) }
        return (0...Int(48.2 * 120)).map { i in
            let t = (Double(i) / 120 * 1e6).rounded() / 1e6
            let p = position(t)
            let down = shelfDemoClicks.contains { t >= $0.t - 1e-9 && t < $0.t + press - 1e-9 }
            return PointerSample(t: t, x: round2(p.x), y: round2(p.y), buttons: down ? 1 : 0, shape: .arrow)
        }
    }
}

import AVFoundation
import CoreVideo

extension SyntheticTake {
    /// A real HEVC movie of a red frame with a blue square sliding right. With `variableRate` the
    /// second from 1.0 to 2.0 s has no frames, the way ScreenCaptureKit sends none for a still screen.
    public static func writeMovie(
        seconds: Double, fps: Int, variableRate: Bool, size: CGSize = CGSize(width: 1440, height: 900), to url: URL
    ) async throws {
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        guard writer.canAdd(input) else { throw CocoaError(.fileWriteUnknown) }
        let video = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: CVPixelBufferCreationAttributes(
            pixelFormatType: CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA),
            size: CVImageSize(width: Int(size.width), height: Int(size.height))
        ))
        try writer.start()
        writer.startSession(atSourceTime: .zero)
        let frames = Int(seconds * Double(fps))
        for i in 0..<frames {
            let t = Double(i) / Double(fps)
            if variableRate && t >= 1 && t < 2 { continue }
            guard let pool = video.pixelBufferPool else { throw CocoaError(.fileWriteUnknown) }
            let buffer = try pool.makeMutablePixelBuffer()
            buffer.withUnsafeBuffer { draw(into: $0, size: size, squareX: 100 + t * 200) }
            let frame = CVReadOnlyPixelBuffer(buffer)
            let time = CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps))
            _ = try await WriterInputAppend.untilAccepted { try video.appendImmediately(frame, with: time) }
        }
        video.finish()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    private static func draw(into buffer: CVPixelBuffer, size: CGSize, squareX: Double) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: squareX, y: size.height / 2 - 20, width: 40, height: 40))
    }
}
