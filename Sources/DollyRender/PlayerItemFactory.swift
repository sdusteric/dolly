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
        public let map: TimeMap
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
        let end = max(min(take.trim.upperBound, sourceDuration), start)
        let map = TimeMap(trim: start...end, regions: take.speedRegions)

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CocoaError(.featureUnsupported)
        }
        // Sound comes from the microphone file when there is one, else from the recording.
        let microphone = folder.appending(path: TakeStore.audioName)
        var sound: Side?
        if let offset = take.microphoneOffset, FileManager.default.fileExists(atPath: microphone.path(percentEncoded: false)) {
            sound = await Side.load(microphone, type: .audio, offset: offset)
        } else if let audio = try await source.loadTracks(withMediaType: .audio).first {
            sound = Side(asset: source, track: audio, offset: 0, length: sourceDuration, type: .audio)
        }
        var webcam: Side?
        if let camera = take.camera {
            webcam = await Side.load(folder.appending(path: camera.file), type: .video, offset: camera.startOffset)
        }
        var soundTrack: AVMutableCompositionTrack?, webcamTrack: AVMutableCompositionTrack?
        var cursor = CMTime.zero
        for piece in map.pieces {
            let range = CMTimeRange(start: time(piece.start), end: time(piece.end))
            try track.insertTimeRange(range, of: video, at: cursor)
            // Sped-up stretches are silent: fast speech is noise.
            if piece.rate == 1, let sound { sound.insert(piece, at: cursor, length: range.duration, into: composition, track: &soundTrack) }
            if let webcam { webcam.insert(piece, at: cursor, length: range.duration, into: composition, track: &webcamTrack) }
            var length = range.duration
            if piece.rate != 1 {
                let scaled = CMTimeMultiplyByFloat64(length, multiplier: 1 / piece.rate)
                composition.scaleTimeRange(CMTimeRange(start: cursor, duration: length), toDuration: scaled)
                length = scaled
            }
            cursor = CMTimeAdd(cursor, length)
        }
        return TakeAsset(asset: composition, inputs: take.compositionInputs, trackID: track.trackID, webcamID: webcamTrack?.trackID,
                         map: map, duration: cursor)
    }

    static func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }

    /// A side file (the webcam or the microphone) or the recording's own sound, where file time 0
    /// is `offset` seconds into the take. A missing, unreadable or empty file is nil, so the take
    /// still plays and exports without it.
    struct Side {
        /// Held so the track's asset lives until the track is inserted.
        let asset: AVAsset
        let track: AVAssetTrack
        let offset: Double
        let length: Double
        let type: AVMediaType

        static func load(_ url: URL, type: AVMediaType, offset: Double) async -> Side? {
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: type).first,
                  let length = try? await asset.load(.duration).seconds, length > 0 else { return nil }
            return Side(asset: asset, track: track, offset: offset, length: length, type: type)
        }

        /// Puts the part of this file that falls inside `piece` at the piece's place in the clip,
        /// making the composition track the first time anything goes in. It never runs past the
        /// piece's video (`length` from `cursor`): AVAssetReader refuses a side track that does.
        func insert(_ piece: TimeMap.Piece, at cursor: CMTime, length: CMTime, into composition: AVMutableComposition,
                    track: inout AVMutableCompositionTrack?) {
            let from = max(piece.start, offset), to = min(piece.end, offset + self.length)
            guard to - from > 0.001 else { return }
            let at = CMTimeAdd(cursor, PlayerItemFactory.time(from - piece.start))
            let duration = CMTimeMinimum(PlayerItemFactory.time(to - from), CMTimeSubtract(CMTimeAdd(cursor, length), at))
            guard duration > .zero else { return }
            if track == nil { track = composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid) }
            guard let target = track else { return }
            let range = CMTimeRange(start: PlayerItemFactory.time(from - offset), duration: duration)
            try? target.insertTimeRange(range, of: self.track, at: at)
        }
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
            camera: camera, pointer: pointer, timeMap: asset.map, webcam: webcam, captions: take.captions,
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
}
