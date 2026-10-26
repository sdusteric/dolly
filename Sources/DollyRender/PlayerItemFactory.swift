import AVFoundation
import DollyCore
import Foundation

/// Builds the trimmed composition and Dolly's video composition for a take in one shape. The
/// player and the exporter both use it; `frameDuration` samples a variable rate master at a steady
/// rate, holding the last source frame between real ones.
public enum PlayerItemFactory {
    public static func composition(
        take: Take, folder: URL, shape: ShapePreset, fps: Int, pointer: PointerPath?
    ) async throws -> (asset: AVAsset, videoComposition: AVVideoComposition) {
        let source = AVURLAsset(url: folder.appending(path: TakeStore.movieName))
        guard let video = try await source.loadTracks(withMediaType: .video).first else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let sourceDuration = try await source.load(.duration).seconds
        let start = max(take.trim.lowerBound, 0)
        let end = min(take.trim.upperBound, sourceDuration)
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                end: CMTime(seconds: end, preferredTimescale: 600))

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CocoaError(.featureUnsupported)
        }
        try track.insertTimeRange(range, of: video, at: .zero)
        if let audio = try await source.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try audioTrack.insertTimeRange(range, of: audio, at: .zero)
        }

        let layout = ShapeLayout(shape: shape, recordingSize: take.size, padding: take.look.padding)
        let camera = CameraPath(zooms: take.zooms, layout: layout,
                                pointer: pointer.map { p in { @Sendable t in p.position(at: t) } }, duration: take.duration)
        let instruction = DollyInstruction(
            timeRange: CMTimeRange(start: .zero, duration: range.duration), trackID: track.trackID,
            composer: FrameComposer(layout: layout, look: take.look, recordingPixelScale: take.pixelScale),
            camera: camera, pointer: pointer, recordingOffset: start
        )
        var configuration = AVVideoComposition.Configuration()
        configuration.customVideoCompositorClass = DollyCompositor.self
        configuration.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        configuration.renderSize = layout.canvas
        configuration.instructions = [instruction]
        configuration.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        configuration.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        configuration.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        return (composition, AVVideoComposition(configuration: configuration))
    }
}
