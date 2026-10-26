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
