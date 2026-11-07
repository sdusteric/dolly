import AppKit
import AVFoundation
import DollyCore
import DollyRender
import Observation

/// The preview (spec 5.2): an AVPlayer on the same composition the exporter uses, kept in step
/// with the editor's playhead, plus the recording frame at the playhead for Aim mode.
@MainActor
@Observable
public final class PreviewPlayer: PlaybackControlling {
    public private(set) var player: AVPlayer?
    public private(set) var isPlaying = false
    /// The recording at 1x with the look, for Aim mode.
    public private(set) var aimImage: CGImage?

    @ObservationIgnored private weak var editor: EditorModel?
    @ObservationIgnored private var folder: URL?
    @ObservationIgnored private var movie: URL?
    @ObservationIgnored private var recordingFrame: CGImage?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    @ObservationIgnored private var frameTask: Task<Void, Never>?
    /// The player item's asset; kept while an edit leaves its inputs alone.
    @ObservationIgnored private var takeAsset: PlayerItemFactory.TakeAsset?
    /// Composition time 0 is the trim start.
    @ObservationIgnored private var offset = 0.0
    @ObservationIgnored private var lastSeek = -1.0
    /// The stage's size in points, from StageView; the Aim still is drawn at about this size.
    @ObservationIgnored private var stagePoints = CGSize.zero
    @ObservationIgnored private var frameNumber = 0
    @ObservationIgnored private var aimRequested: AimKey?
    @ObservationIgnored private var aimRenderer: LatestOnly<AimRequest, AimResult>?

    private struct AimKey: Equatable {
        let inputs: AimInputs
        let frame: Int
        let scale: Double
    }

    private struct AimRequest: Sendable {
        let take: Take
        let folder: URL?
        let recording: CGImage
        let scale: Double
    }

    private struct AimResult: Sendable {
        let image: CGImage?
        let takeID: UUID
    }

    public init() {
        aimRenderer = LatestOnly(work: { request in
            AimResult(image: StillRenderer.render(take: request.take, folder: request.folder, recording: request.recording,
                                                  camera: nil, pointer: nil, ring: nil, scale: request.scale),
                      takeID: request.take.id)
        }, deliver: { [weak self] result in
            // A still from the take that was open before never replaces this one's.
            guard let self, let image = result.image, self.editor?.take.id == result.takeID else { return }
            self.aimImage = image
        })
    }

    public func load(editor: EditorModel, folder: URL) {
        self.editor = editor
        self.folder = folder
        resetAim()
        takeAsset = nil
        movie = folder.appending(path: TakeStore.movieName)
        rebuild(after: .zero)
        watchPlayhead(editor)
    }

    /// From StageView. A bigger stage draws the Aim still again, a smaller one keeps it.
    public func stageResized(_ size: CGSize) {
        stagePoints = size
        if editor?.selectedZoom != nil { renderAim() }
    }

    private func resetAim() {
        aimRenderer?.cancel()
        aimRequested = nil
        aimImage = nil
        recordingFrame = nil
    }

    /// The open take went to the Trash and no other take is left to show.
    public func unload() {
        pause()
        rebuildTask?.cancel()
        frameTask?.cancel()
        player?.replaceCurrentItem(with: nil)
        editor = nil
        folder = nil
        movie = nil
        takeAsset = nil
        resetAim()
    }

    public func takeChanged() {
        rebuild(after: .milliseconds(150))
        renderAim()
    }

    // MARK: PlaybackControlling

    public func togglePlay() {
        isPlaying ? pause() : play(rate: 1)
    }

    public func shuttle(_ rate: Double) {
        rate == 0 ? pause() : play(rate: rate)
    }

    public func pause() {
        player?.pause()
        isPlaying = false
    }

    private func play(rate: Double) {
        guard let player, let editor, let item = player.currentItem else { return }
        if rate < 0, !item.canPlayReverse {
            editor.playhead = max(editor.playhead - 1, editor.take.trim.lowerBound)
            return
        }
        if rate > 0, editor.playhead >= editor.take.trim.upperBound - 0.05 {
            editor.playhead = editor.take.trim.lowerBound
            seek(to: editor.playhead)
        }
        player.rate = Float(rate)
        isPlaying = true
    }

    // MARK: Player item

    private func rebuild(after delay: Duration) {
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self, let editor, let folder else { return }
            let take = editor.take
            // Twice the canvas on a Retina screen: the stage is wider than 1080p there, and a zoom
            // would otherwise show a stretched frame instead of the recording's own pixels.
            let scale = min(NSScreen.main?.backingScaleFactor ?? 1, 2)
            do {
                // Look and zoom edits keep the asset and the item; only the compositor's instruction changes.
                if let kept = takeAsset, kept.inputs == take.compositionInputs, let item = player?.currentItem {
                    let composition = await PlayerItemFactory.videoComposition(take: take, folder: folder, asset: kept,
                                                                               shape: take.currentShape, fps: 60,
                                                                               pointer: editor.pointer, renderScale: scale)
                    guard !Task.isCancelled else { return }
                    item.videoComposition = composition
                    if !isPlaying { seek(to: editor.playhead, force: true) }
                    return
                }
                let built = try await PlayerItemFactory.asset(take: take, folder: folder)
                let composition = await PlayerItemFactory.videoComposition(take: take, folder: folder, asset: built,
                                                                           shape: take.currentShape, fps: 60,
                                                                           pointer: editor.pointer, renderScale: scale)
                guard !Task.isCancelled else { return }
                takeAsset = built
                install(AVPlayerItem(asset: built.asset), videoComposition: composition, take: take)
            } catch {
                if let timeObserver { player?.removeTimeObserver(timeObserver) }
                timeObserver = nil
                player = nil
                takeAsset = nil
            }
        }
    }

    private func install(_ item: AVPlayerItem, videoComposition: AVVideoComposition, take: Take) {
        item.videoComposition = videoComposition
        offset = take.trim.lowerBound
        let wasPlaying = isPlaying
        let player = player ?? makePlayer()
        player.replaceCurrentItem(with: item)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item,
                                                             queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isPlaying = false }
        }
        if let editor { seek(to: editor.playhead, force: true) }
        if wasPlaying { player.play() }
    }

    private func makePlayer() -> AVPlayer {
        let player = AVPlayer()
        player.actionAtItemEnd = .pause
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying, let editor = self.editor else { return }
                let t = self.offset + time.seconds
                self.lastSeek = t
                editor.playhead = t
            }
        }
        self.player = player
        return player
    }

    private func seek(to t: Double, force: Bool = false) {
        guard let player, force || abs(t - lastSeek) > 0.0005 else { return }
        lastSeek = t
        let time = CMTime(seconds: max(t - offset, 0), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Scrubbing while paused moves the player; while playing the player moves the playhead.
    private func watchPlayhead(_ editor: EditorModel) {
        let id = ObjectIdentifier(editor)
        withObservationTracking {
            _ = editor.playhead
            _ = editor.selectedZoom
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, let editor = self.editor, ObjectIdentifier(editor) == id else { return }
                if !self.isPlaying {
                    self.seek(to: editor.playhead)
                    self.refreshFrame()
                } else if abs(editor.playhead - self.lastSeek) > 0.05 {
                    // A click on the ruler while playing: the player jumps there and plays on.
                    self.seek(to: editor.playhead, force: true)
                }
                self.watchPlayhead(editor)
            }
        }
    }

    // MARK: Frames

    private func refreshFrame() {
        guard let editor, editor.selectedZoom != nil, let movie else { return }
        frameTask?.cancel()
        let t = editor.playhead
        // The recording never needs more pixels than the canvas it is drawn into.
        let canvas = editor.take.currentShape.pixelSize(recording: editor.take.size)
        let limit = CGSize(width: canvas.width, height: canvas.height)
        frameTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled, let image = await Self.frame(of: movie, at: t, maximumSize: limit) else { return }
            guard let self, !Task.isCancelled else { return }
            recordingFrame = image
            frameNumber += 1
            renderAim()
        }
    }

    /// Draws the Aim still off the main actor at the stage's size. Zoom edits (aim, depth) do not
    /// change it, so only a new frame, a look edit or a bigger stage draws again; the old still
    /// stays up until the new one is ready.
    private func renderAim() {
        guard let editor, let recordingFrame, let aimRenderer else { return }
        let take = editor.take
        let canvas = take.currentShape.pixelSize(recording: take.size)
        let backing = NSScreen.main?.backingScaleFactor ?? 2
        let stage = CGSize(width: stagePoints.width * backing, height: stagePoints.height * backing)
        let scale = StillRenderer.previewScale(canvas: CGSize(width: canvas.width, height: canvas.height), stagePixels: stage)
        let key = AimKey(inputs: take.aimInputs, frame: frameNumber, scale: scale)
        // A smaller stage keeps the sharper still it has.
        if let last = aimRequested, last.inputs == key.inputs, last.frame == key.frame, last.scale >= key.scale { return }
        aimRequested = key
        aimRenderer.submit(AimRequest(take: take, folder: folder, recording: recordingFrame, scale: scale))
    }

    /// The output at the playhead in every shape, for the export sheet's plates.
    public func outputStills() async -> [ShapePreset: CGImage] {
        guard let editor, let movie, let folder else { return [:] }
        let take = editor.take
        let t = editor.playhead
        guard let frame = await Self.frame(of: movie, at: t) else { return [:] }
        var cameraFrame: CGImage?
        if let camera = take.camera {
            cameraFrame = await Self.frame(of: folder.appending(path: camera.file), at: max(t - camera.startOffset, 0))
        }
        let pointer = editor.pointer
        var stills: [ShapePreset: CGImage] = [:]
        for shape in ShapePreset.allCases {
            let layout = ShapeLayout(shape: shape, recordingSize: take.size, padding: take.look.padding)
            let path = CameraPath(zooms: take.zooms, layout: layout, pointer: pointer.map { p in { @Sendable t in p.position(at: t) } },
                                  duration: take.duration)
            stills[shape] = StillRenderer.render(take: take, folder: folder, shape: shape, recording: frame, camera: path.camera(at: t),
                                                 pointer: pointer?.position(at: t).map { ($0, pointer?.shape(at: t) ?? .arrow) },
                                                 ring: pointer?.ring(at: t).map { ($0.center, $0.progress) },
                                                 cameraFrame: cameraFrame, at: t, depthProgress: path.depthProgress(at: t))
        }
        return stills
    }

    /// One recording frame, within a frame of `t`, no bigger than `maximumSize` when given.
    nonisolated private static func frame(of movie: URL, at t: Double, maximumSize: CGSize? = nil) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
        if let maximumSize { generator.maximumSize = maximumSize }
        let tolerance = CMTime(value: 1, timescale: 60)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        return try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
    }
}
