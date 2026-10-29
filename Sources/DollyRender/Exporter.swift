import AVFoundation
import DollyCore
import Foundation

/// Writes one shape of a take as an mp4 (spec 7): Dolly's compositor through
/// `AVAssetReaderVideoCompositionOutput` into H.264 High at the plan's bit rate, moov first, to a
/// hidden temp name and then a free final name, so nothing is ever overwritten. Cancellable.
public final class Exporter: ExportRunning {
    public init() {}

    public func export(
        _ plan: ExportPlan, takeFolder: URL, pointer: PointerPath?, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try Task.checkCancellation()
        let (asset, composition) = try await PlayerItemFactory.composition(
            take: plan.take, folder: takeFolder, shape: plan.shape, fps: plan.fps, pointer: pointer
        )
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let duration = try await asset.load(.duration).seconds
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderVideoCompositionOutput(videoTracks: tracks, videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.videoComposition = composition
        guard reader.canAdd(output) else { throw CocoaError(.featureUnsupported) }
        let provider = reader.outputProvider(for: output)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var audioOutput: AVAssetReaderAudioMixOutput?
        if !audioTracks.isEmpty {
            let mix = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            guard reader.canAdd(mix) else { throw CocoaError(.featureUnsupported) }
            audioOutput = mix
        }
        let audioProvider = audioOutput.map { reader.outputProvider(for: $0) }

        // AVFoundation leaves its own scratch files beside the output while it moves the moov box
        // first, so the export happens in a hidden folder of its own that is removed afterwards.
        let scratch = plan.folder.appending(path: ".dolly-export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let temp = scratch.appending(path: "export.mp4")
        let size = plan.shape.pixelSize(recording: plan.take.size)
        let writer = try AVAssetWriter(outputURL: temp, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: plan.bitRate, AVVideoExpectedSourceFrameRateKey: plan.fps,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel, AVVideoMaxKeyFrameIntervalKey: plan.fps * 2,
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        guard writer.canAdd(input) else { throw CocoaError(.featureUnsupported) }
        let receiver = writer.inputReceiver(for: input)
        var audioReceiver: AVAssetWriterInput.SampleBufferReceiver?
        if audioProvider != nil {
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 160_000,
            ])
            guard writer.canAdd(audioInput) else { throw CocoaError(.featureUnsupported) }
            audioReceiver = writer.inputReceiver(for: audioInput)
        }

        func discard() {
            writer.cancelWriting()
            reader.cancelReading()
        }
        do {
            try reader.start()
            try writer.start()
            writer.startSession(atSourceTime: .zero)
            let expected = max(duration * Double(plan.fps), 1)
            // Video and audio are read in step, whichever is behind first: the reader stalls when one
            // output runs far ahead of the other.
            var frames = 0.0
            var reported = -1.0
            var videoAt = -Double.infinity, audioAt = -Double.infinity
            var videoDone = false, audioDone = audioProvider == nil
            while !videoDone || !audioDone {
                try Task.checkCancellation()
                if !videoDone && (audioDone || videoAt <= audioAt) {
                    guard let sample = try await provider.next() else {
                        receiver.finish()
                        videoDone = true
                        continue
                    }
                    videoAt = sample.presentationTimeStamp.seconds
                    _ = try await WriterInputAppend.untilAccepted { try receiver.appendImmediately(sample) }
                    frames += Double(sample.sampleCount)
                    let fraction = min(frames / expected, 0.99)
                    if fraction - reported >= 0.05 {
                        progress(fraction)
                        reported = fraction
                    }
                } else if let audioProvider, let audioReceiver {
                    guard let sample = try await audioProvider.next() else {
                        audioReceiver.finish()
                        audioDone = true
                        continue
                    }
                    audioAt = sample.presentationTimeStamp.seconds
                    _ = try await WriterInputAppend.untilAccepted { try audioReceiver.appendImmediately(sample) }
                }
            }
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        } catch {
            discard()
            throw error
        }
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: plan.folder.path(percentEncoded: false))) ?? [])
        let final = plan.outputURL(existing: existing)
        try FileManager.default.moveItem(at: temp, to: final)
        progress(1)
        return final
    }
}
