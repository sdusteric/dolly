import AVFoundation
import CoreVideo
import Foundation

/// Writes `take.mov` (spec 4.2): HEVC, BT.709, with a movie fragment every 2 s so a killed Dolly
/// leaves a file that plays up to the last fragment (plan Review Focus 1). Times are seconds from
/// the first frame; frames arrive at whatever rate the screen changed.
public final class MasterWriter {
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput.PixelBufferReceiver
    private var started = false

    public init(url: URL, pixelSize: PixelSize, fps: Int, realTime: Bool = false) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.movieFragmentInterval = CMTime(seconds: RecordingPlan.fragmentInterval, preferredTimescale: 600)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: pixelSize.width, AVVideoHeightKey: pixelSize.height,
            AVVideoCompressionPropertiesKey: [AVVideoExpectedSourceFrameRateKey: fps, AVVideoQualityKey: 0.85],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        input.expectsMediaDataInRealTime = realTime
        guard writer.canAdd(input) else { throw RecordingSourceError.couldNotStart("cannot add the video input") }
        video = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: CVPixelBufferCreationAttributes(
            pixelFormatType: CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA),
            size: CVImageSize(width: pixelSize.width, height: pixelSize.height)
        ))
    }

    public func append(_ frame: CVReadOnlyPixelBuffer, at time: CMTime) async throws {
        if !started {
            try writer.start()
            writer.startSession(atSourceTime: .zero)
            started = true
        }
        _ = try await WriterInputAppend.untilAccepted { try video.appendImmediately(frame, with: time) }
    }

    public func finish() async throws {
        guard started else { throw RecordingSourceError.notRecording }
        video.finish()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? RecordingSourceError.notRecording }
    }

    /// Stops without finishing, as a crash would. Tests only.
    public func abandon() { writer.cancelWriting() }
}

/// Plain frames for tests and fakes.
public enum SyntheticFrames {
    public static func solid(width: Int, height: Int, shade: UInt8) throws -> CVReadOnlyPixelBuffer {
        var buffer = try CVMutablePixelBuffer(CVPixelBufferCreationAttributes(
            pixelFormatType: CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA), size: CVImageSize(width: width, height: height)
        ))
        buffer.withUnsafeBuffer { pixel in
            CVPixelBufferLockBaseAddress(pixel, [])
            defer { CVPixelBufferUnlockBaseAddress(pixel, []) }
            if let base = CVPixelBufferGetBaseAddress(pixel) {
                memset(base, Int32(shade), CVPixelBufferGetBytesPerRow(pixel) * height)
            }
        }
        return CVReadOnlyPixelBuffer(buffer)
    }
}
