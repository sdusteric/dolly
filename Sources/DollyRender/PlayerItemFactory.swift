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
        let microphone = folder.appending(path: TakeStore.audioName)
        if let offset = take.microphoneOffset, FileManager.default.fileExists(atPath: microphone.path(percentEncoded: false)) {
            _ = try await insertSide(microphone, type: .audio, offset: offset, trim: start...end, into: composition)
        } else if let audio = try await source.loadTracks(withMediaType: .audio).first,
                  let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try audioTrack.insertTimeRange(range, of: audio, at: .zero)
        }
        var webcam: (trackID: CMPersistentTrackID, track: CameraTrack)?
        if let camera = take.camera,
           let id = try await insertSide(folder.appending(path: camera.file), type: .video, offset: camera.startOffset,
                                         trim: start...end, into: composition) {
            webcam = (id, camera)
        }

        let layout = ShapeLayout(shape: shape, recordingSize: take.size, padding: take.look.padding)
        let camera = CameraPath(zooms: take.zooms, layout: layout,
                                pointer: pointer.map { p in { @Sendable t in p.position(at: t) } }, duration: take.duration)
        let instruction = DollyInstruction(
            timeRange: CMTimeRange(start: .zero, duration: range.duration), trackID: track.trackID,
            composer: FrameComposer.make(take: take, folder: folder, layout: layout),
            camera: camera, pointer: pointer, recordingOffset: start, webcam: webcam, captions: take.captions
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

    /// Puts the part of a side file (the webcam or the microphone) that falls inside the trim into
    /// the composition, where file time 0 is `offset` seconds into the take. A missing or unreadable
    /// file adds nothing, so the take still plays and exports.
    static func insertSide(_ url: URL, type: AVMediaType, offset: Double, trim: ClosedRange<Double>,
                           into composition: AVMutableComposition) async throws -> CMPersistentTrackID? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        let asset = AVURLAsset(url: url)
        guard let sourceTrack = try? await asset.loadTracks(withMediaType: type).first,
              let length = try? await asset.load(.duration).seconds, length > 0 else { return nil }
        let from = max(trim.lowerBound - offset, 0), to = min(trim.upperBound - offset, length)
        guard to > from, let track = composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return nil
        }
        let range = CMTimeRange(start: CMTime(seconds: from, preferredTimescale: 600), end: CMTime(seconds: to, preferredTimescale: 600))
        try track.insertTimeRange(range, of: sourceTrack, at: CMTime(seconds: max(offset - trim.lowerBound, 0), preferredTimescale: 600))
        return track.trackID
    }
}
