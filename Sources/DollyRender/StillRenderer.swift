import CoreGraphics
import CoreImage
import DollyCore
import Foundation

/// One composed frame as a CGImage: the stage's still in Aim mode, shot mode, and dollyctl render.
public enum StillRenderer {
    static let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    public static func render(
        take: Take, shape: ShapePreset = .wide16x9, recording: CGImage, camera: CameraState?,
        pointer: (CGPoint, PointerShape)?, ring: (CGPoint, Double)?
    ) -> CGImage? {
        let layout = ShapeLayout(shape: shape, recordingSize: take.size, padding: take.look.padding)
        let composer = FrameComposer(layout: layout, look: take.look, recordingPixelScale: take.pixelScale)
        let image = composer.compose(recording: CIImage(cgImage: recording), camera: camera ?? layout.rest,
                                     pointer: pointer.map { ($0.0, $0.1) }, ring: ring.map { ($0.0, $0.1) })
        return context.createCGImage(image, from: CGRect(origin: .zero, size: layout.canvas),
                                     format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }
}
