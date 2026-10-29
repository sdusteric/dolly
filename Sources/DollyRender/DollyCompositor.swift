import AVFoundation
import CoreImage
import DollyCore
import Foundation

/// What the compositor needs for every frame of one composition. Immutable after init, so it is
/// safe to hand to AVFoundation's render threads (the documented `@unchecked Sendable` boundary).
final class DollyInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let trackID: CMPersistentTrackID
    let composer: FrameComposer
    let camera: CameraPath
    let pointer: PointerPath?
    /// Composition time 0 is this many seconds into the recording (the trim's start).
    let recordingOffset: Double
    /// The webcam's track in the composition, and how to draw it.
    let webcam: (trackID: CMPersistentTrackID, track: CameraTrack)?
    let captions: CaptionTrack?

    init(timeRange: CMTimeRange, trackID: CMPersistentTrackID, composer: FrameComposer, camera: CameraPath,
         pointer: PointerPath?, recordingOffset: Double, webcam: (trackID: CMPersistentTrackID, track: CameraTrack)? = nil,
         captions: CaptionTrack? = nil) {
        self.timeRange = timeRange
        self.trackID = trackID
        requiredSourceTrackIDs = [trackID, webcam?.trackID].compactMap { $0 }.map { NSNumber(value: $0) }
        self.composer = composer
        self.camera = camera
        self.pointer = pointer
        self.recordingOffset = recordingOffset
        self.webcam = webcam
        self.captions = captions
    }
}

/// Renders Dolly's frames for both the preview player and the exporter, so what plays is what
/// exports (spec 5.2). AVFoundation calls it on its own threads; CIContext is thread-safe.
final class DollyCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    static let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    /// Frames are tagged BT.709 (the composition says so), so they are rendered in that space.
    static let outputSpace = CGColorSpace(name: CGColorSpace.coreMedia709)

    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? DollyInstruction,
              let source = request.sourceReadOnlyPixelBuffer(byTrackID: instruction.trackID) else {
            request.finish(with: CocoaError(.featureUnsupported))
            return
        }
        let output: CVMutablePixelBuffer
        do {
            output = try request.renderContext.makeMutablePixelBuffer()
        } catch {
            request.finish(with: error)
            return
        }
        let t = request.compositionTime.seconds + instruction.recordingOffset
        let pointer = instruction.pointer
        let webcam = instruction.webcam.flatMap { $0.track.isVisible(at: t) ? $0 : nil }
        let webcamBuffer = webcam.flatMap { request.sourceReadOnlyPixelBuffer(byTrackID: $0.trackID) }
        let caption = instruction.captions?.caption(at: t)?.text
        // Every buffer is only valid inside its closure, so the render happens in there.
        let bounds = CGRect(origin: .zero, size: instruction.composer.layout.canvas)
        source.withUnsafeBuffer { sourceBuffer in
            let recording = CIImage(cvPixelBuffer: sourceBuffer)
            let frame = { (cameraFrame: CIImage?) in
                instruction.composer.compose(
                    recording: recording, camera: instruction.camera.camera(at: t),
                    pointer: pointer?.position(at: t).map { ($0, pointer?.shape(at: t) ?? .arrow) },
                    ring: pointer?.ring(at: t), cameraFrame: cameraFrame,
                    cameraState: webcam.map { ($0.track, instruction.camera.depthProgress(at: t)) }, caption: caption
                )
            }
            if let webcamBuffer {
                webcamBuffer.withUnsafeBuffer { cameraBuffer in
                    let image = frame(CIImage(cvPixelBuffer: cameraBuffer))
                    output.withUnsafeBuffer { Self.context.render(image, to: $0, bounds: bounds, colorSpace: Self.outputSpace) }
                }
            } else {
                let image = frame(nil)
                output.withUnsafeBuffer { Self.context.render(image, to: $0, bounds: bounds, colorSpace: Self.outputSpace) }
            }
        }
        request.finish(withComposedPixelBuffer: CVReadOnlyPixelBuffer(output))
    }
}
