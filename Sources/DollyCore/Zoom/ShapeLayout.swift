import CoreGraphics
import Foundation

/// The camera: a depth and where the view is centered, in canvas pixels.
public struct CameraState: Hashable, Sendable {
    public var depth: Double
    public var center: CGPoint

    public init(depth: Double, center: CGPoint) {
        self.depth = depth
        self.center = center
    }

    func lerp(to other: CameraState, _ u: Double) -> CameraState {
        CameraState(depth: depth + (other.depth - depth) * u,
                    center: CGPoint(x: center.x + (other.center.x - center.x) * u,
                                    y: center.y + (other.center.y - center.y) * u))
    }
}

/// Where the recording sits in one export shape (spec 5.3), and what a camera shows of it.
public struct ShapeLayout: Sendable, Hashable {
    public let shape: ShapePreset
    public let recordingSize: CGSize
    public let canvas: CGSize
    public let recordingRect: CGRect

    /// `padding` is in points at a 1080 px short side and scales with the output.
    public init(shape: ShapePreset, recordingSize: CGSize, padding: Double) {
        self.shape = shape
        self.recordingSize = recordingSize
        canvas = CGSize(width: shape.pixelSize.width, height: shape.pixelSize.height)
        let pad = padding * min(canvas.width, canvas.height) / 1080
        let scale = min((canvas.width - 2 * pad) / max(recordingSize.width, 1),
                        (canvas.height - 2 * pad) / max(recordingSize.height, 1))
        let size = CGSize(width: recordingSize.width * scale, height: recordingSize.height * scale)
        recordingRect = CGRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2,
                               width: size.width, height: size.height)
    }

    public var scale: Double { recordingRect.width / max(recordingSize.width, 1) }
    public var rest: CameraState { CameraState(depth: 1, center: CGPoint(x: recordingRect.midX, y: recordingRect.midY)) }

    public func canvasPoint(_ recording: CGPoint) -> CGPoint {
        CGPoint(x: recordingRect.minX + recording.x * scale, y: recordingRect.minY + recording.y * scale)
    }

    /// The part of the canvas the camera shows. On an axis where the view is at least as big as the
    /// recording it centers on the recording; otherwise it stays inside the recording.
    public func viewRect(_ camera: CameraState) -> CGRect {
        let w = canvas.width / camera.depth, h = canvas.height / camera.depth
        func axis(_ c: Double, _ v: Double, _ lo: Double, _ len: Double) -> Double {
            v >= len ? lo + len / 2 : min(max(c, lo + v / 2), lo + len - v / 2)
        }
        let cx = axis(camera.center.x, w, recordingRect.minX, recordingRect.width)
        let cy = axis(camera.center.y, h, recordingRect.minY, recordingRect.height)
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }
}
