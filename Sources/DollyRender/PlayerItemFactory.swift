import AVFoundation
import DollyCore
import Foundation

/// Builds the trimmed composition and Dolly's video composition for a take in one shape. The
/// player and the exporter both use it; `frameDuration` samples a variable rate master at a steady
/// rate, holding the last source frame between real ones. `renderScale` renders more pixels than
/// the canvas (the editor's preview on a Retina screen); exports use 1.
public enum PlayerItemFactory {
    /// The trimmed recording with its sound and webcam tracks, and what it was built from. The
    /// composition is never changed after `asset(take:folder:)` returns it, so it can cross actors.
    public struct TakeAsset: @unchecked Sendable {
        public let asset: AVAsset
        public let inputs: CompositionInputs
        let trackID: CMPersistentTrackID
        let webcamID: CMPersistentTrackID?
        let start: Double
        let duration: CMTime
    }

    public static func composition(
        take: Take, folder: URL, shape: ShapePreset, fps: Int, pointer: PointerPath?, renderScale: Double = 1
    ) async throws -> (asset: AVAsset, videoComposition: AVVideoComposition) {
        let built = try await asset(take: take, folder: folder)
        return (built.asset, await videoComposition(take: take, folder: folder, asset: built, shape: shape, fps: fps, pointer: pointer,
                                              renderScale: renderScale))
    }

    public static func asset(take: Take, folder: URL) async throws -> TakeAsset {
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
            _ = try await insertSide(microphone, type: .audio, offset: offset, trim: start...end, limit: range.duration,
                                     into: composition)
        } else if let audio = try await source.loadTracks(withMediaType: .audio).first,
                  let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try audioTrack.insertTimeRange(range, of: audio, at: .zero)
        }
        var webcamID: CMPersistentTrackID?
        if let camera = take.camera {
            webcamID = try await insertSide(folder.appending(path: camera.file), type: .video, offset: camera.startOffset,
                                            trim: start...end, limit: range.duration, into: composition)
        }
        return TakeAsset(asset: composition, inputs: take.compositionInputs, trackID: track.trackID, webcamID: webcamID,
                         start: start, duration: range.duration)
    }

    /// Dolly's compositor over `asset` for the take as it is now. Much cheaper than the asset, so the
    /// preview builds a new one for a look or zoom edit and keeps the asset. Off the caller's actor,
    /// since a picture backdrop is read from disk.
    @concurrent public static func videoComposition(
        take: Take, folder: URL, asset: TakeAsset, shape: ShapePreset, fps: Int, pointer: PointerPath?, renderScale: Double = 1
    ) async -> AVVideoComposition {
        let layout = ShapeLayout(shape: shape, recordingSize: take.size, padding: take.look.padding)
        let camera = CameraPath(zooms: take.zooms, layout: layout,
                                pointer: pointer.map { p in { @Sendable t in p.position(at: t) } }, duration: take.duration)
        var webcam: (trackID: CMPersistentTrackID, track: CameraTrack)?
        if let id = asset.webcamID, let track = take.camera { webcam = (id, track) }
        let instruction = DollyInstruction(
            timeRange: CMTimeRange(start: .zero, duration: asset.duration), trackID: asset.trackID,
            composer: FrameComposer.make(take: take, folder: folder, layout: layout, detail: renderScale),
            camera: camera, pointer: pointer, recordingOffset: asset.start, webcam: webcam, captions: take.captions,
            renderScale: renderScale
        )
        var configuration = AVVideoComposition.Configuration()
        configuration.customVideoCompositorClass = DollyCompositor.self
        configuration.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        configuration.renderSize = CGSize(width: layout.canvas.width * renderScale, height: layout.canvas.height * renderScale)
        configuration.instructions = [instruction]
        configuration.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        configuration.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        configuration.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        return AVVideoComposition(configuration: configuration)
    }

    /// Puts the part of a side file (the webcam or the microphone) that falls inside the trim into
    /// the composition, where file time 0 is `offset` seconds into the take. It never runs past
    /// `limit`, the trimmed video's length, which the one compositor instruction covers. A missing,
    /// unreadable or odd file adds nothing, so the take still plays and exports.
    static func insertSide(_ url: URL, type: AVMediaType, offset: Double, trim: ClosedRange<Double>, limit: CMTime,
                           into composition: AVMutableComposition) async throws -> CMPersistentTrackID? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        let asset = AVURLAsset(url: url)
        guard let sourceTrack = try? await asset.loadTracks(withMediaType: type).first,
              let length = try? await asset.load(.duration).seconds, length > 0 else { return nil }
        let from = max(trim.lowerBound - offset, 0), to = min(trim.upperBound - offset, length)
        guard to > from, let track = composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return nil
        }
        let at = CMTime(seconds: max(offset - trim.lowerBound, 0), preferredTimescale: 600)
        let duration = CMTimeMinimum(CMTime(seconds: to - from, preferredTimescale: 600), CMTimeSubtract(limit, at))
        guard duration > .zero else {
            composition.removeTrack(track)
            return nil
        }
        do {
            try track.insertTimeRange(CMTimeRange(start: CMTime(seconds: from, preferredTimescale: 600), duration: duration),
                                      of: sourceTrack, at: at)
        } catch {
            composition.removeTrack(track)
            return nil
        }
        return track.trackID
    }
}
