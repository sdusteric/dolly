import CoreGraphics
import CoreImage
import DollyCore
import Foundation

/// One composed frame as a CGImage: the stage's still in Aim mode, shot mode, the export sheet's
/// plates, and dollyctl render.
public enum StillRenderer {
    static let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    /// `shape` defaults to the take's own. With a time `t`, the webcam (from `cameraFrame`) and the
    /// caption at that time are drawn too; without one, the bare recording with its look.
    public static func render(
        take: Take, folder: URL? = nil, shape: ShapePreset? = nil, recording: CGImage, camera: CameraState?,
        pointer: (CGPoint, PointerShape)?, ring: (CGPoint, Double)?, cameraFrame: CGImage? = nil, at t: Double? = nil,
        depthProgress: Double = 0
    ) -> CGImage? {
        let layout = ShapeLayout(shape: shape ?? take.currentShape, recordingSize: take.size, padding: take.look.padding)
        let composer = FrameComposer.make(take: take, folder: folder, layout: layout)
        let webcam = t.flatMap { t in take.camera.flatMap { $0.isVisible(at: t) ? $0 : nil } }
        let image = composer.compose(recording: CIImage(cgImage: recording), camera: camera ?? layout.rest,
                                     pointer: pointer.map { ($0.0, $0.1) }, ring: ring.map { ($0.0, $0.1) },
                                     cameraFrame: cameraFrame.map { CIImage(cgImage: $0) },
                                     cameraState: webcam.map { ($0, depthProgress) },
                                     caption: t.flatMap { take.captions?.caption(at: $0)?.text })
        return context.createCGImage(image, from: CGRect(origin: .zero, size: layout.canvas),
                                     format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }
}
