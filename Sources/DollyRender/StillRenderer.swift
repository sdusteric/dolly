import CoreGraphics
import CoreImage
import DollyCore
import Foundation

/// One composed frame as a CGImage: the stage's still in Aim mode, shot mode, the export sheet's
/// plates, and dollyctl render.
public enum StillRenderer {
    static let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    /// `shape` defaults to the take's own. With a time `t`, the webcam (from `cameraFrame`) and the
    /// caption at that time are drawn too; without one, the bare recording with its look. `scale`
    /// below 1 draws a smaller image of the same frame, for the stage.
    public static func render(
        take: Take, folder: URL? = nil, shape: ShapePreset? = nil, recording: CGImage, camera: CameraState?,
        pointer: (CGPoint, PointerShape)?, ring: (CGPoint, Double)?, cameraFrame: CGImage? = nil, at t: Double? = nil,
        depthProgress: Double = 0, scale: Double = 1
    ) -> CGImage? {
        let layout = ShapeLayout(shape: shape ?? take.currentShape, recordingSize: take.size, padding: take.look.padding)
        let composer = FrameComposer.make(take: take, folder: folder, layout: layout)
        let webcam = t.flatMap { t in take.camera.flatMap { $0.isVisible(at: t) ? $0 : nil } }
        let image = composer.compose(recording: CIImage(cgImage: recording), camera: camera ?? layout.rest,
                                     pointer: pointer.map { ($0.0, $0.1) }, ring: ring.map { ($0.0, $0.1) },
                                     cameraFrame: cameraFrame.map { CIImage(cgImage: $0) },
                                     cameraState: webcam.map { ($0, depthProgress) },
                                     caption: t.flatMap { take.captions?.caption(at: $0)?.text })
        let out = scale == 1 ? image : image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let size = CGSize(width: (layout.canvas.width * scale).rounded(), height: (layout.canvas.height * scale).rounded())
        return context.createCGImage(out, from: CGRect(origin: .zero, size: size),
                                     format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    /// The scale that fits `canvas` into the stage's pixels: never above 1, never below a quarter,
    /// and 1 while the stage size is not known yet.
    public static func previewScale(canvas: CGSize, stagePixels: CGSize) -> Double {
        guard stagePixels.width > 0, stagePixels.height > 0, canvas.width > 0, canvas.height > 0 else { return 1 }
        let fit = min(stagePixels.width / canvas.width, stagePixels.height / canvas.height)
        return min(max(fit, 0.25), 1)
    }
}
