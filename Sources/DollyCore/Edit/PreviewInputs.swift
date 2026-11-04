import CoreGraphics
import Foundation

/// What the preview's AVMutableComposition is built from. Edits that leave these alone (look,
/// zooms, shape, captions, the camera bubble's look) only need a new video composition.
public struct CompositionInputs: Hashable, Sendable {
    public let trim: ClosedRange<Double>
    public let microphoneOffset: Double?
    public let cameraFile: String?
    public let cameraOffset: Double?
}

/// What the Aim still is drawn from: the recording at 1x with the look, in the take's shape.
public struct AimInputs: Hashable, Sendable {
    public let look: Look
    public let shape: ShapePreset
    public let size: CGSize

    public static func == (a: AimInputs, b: AimInputs) -> Bool {
        a.look == b.look && a.shape == b.shape && a.size == b.size
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(look)
        hasher.combine(shape)
        hasher.combine(size.width)
        hasher.combine(size.height)
    }
}

extension Take {
    public var compositionInputs: CompositionInputs {
        CompositionInputs(trim: trim, microphoneOffset: microphoneOffset, cameraFile: camera?.file, cameraOffset: camera?.startOffset)
    }

    public var aimInputs: AimInputs { AimInputs(look: look, shape: currentShape, size: size) }
}
