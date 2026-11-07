import CoreGraphics
import Foundation

public enum RecordingPlanError: Error, Sendable, Hashable { case tooSmall }

/// Everything the live source passes to ScreenCaptureKit, decided before recording (spec 4.2),
/// so the live code only copies fields.
public struct RecordingPlan: Sendable, Hashable {
    public static let minimumPixelSide = 64
    public static let fragmentInterval = 2.0
    public static let maxSeconds = 1800.0
    public static let warnSeconds = 300.0

    public var target: TargetKind
    public var displayID: UInt32
    public var windowID: UInt32?
    /// The recorded content in global points (for a window, its frame when recording starts).
    public var globalRect: CGRect
    public var scale: Double
    public var pixelSize: PixelSize
    public var fps = 60
    public var queueDepth = 6
    /// Dolly draws its own pointer (spec 4.7).
    public var showsCursor = false
    public var excludedWindowIDs: [UInt32] = []
    /// The camera and microphone to record beside the screen; nil when the switch is off.
    public var cameraID: String?
    public var microphoneID: String?
    /// Record the sound other apps play (ScreenCaptureKit, no extra permission).
    public var systemAudio = false
    /// What the take is named after (TakeName); nil names it "Untitled take N".
    public var nameHint: String?

    public var size: CGSize { globalRect.size }

    /// `pixelSize` overrides the computed size (small test movies).
    public static func make(
        target: TargetKind, displayID: UInt32, windowID: UInt32?, globalRect: CGRect, scale: Double, pixelSize: PixelSize? = nil
    ) throws -> RecordingPlan {
        let even = { (v: Double) in Int(v) / 2 * 2 }
        let pixels = pixelSize ?? PixelSize(width: even(globalRect.width * scale), height: even(globalRect.height * scale))
        guard pixels.width >= minimumPixelSide, pixels.height >= minimumPixelSide else { throw RecordingPlanError.tooSmall }
        return RecordingPlan(target: target, displayID: displayID, windowID: windowID, globalRect: globalRect,
                             scale: scale, pixelSize: pixels)
    }

    public func geometry(windowFrames: [WindowFrameSample]) -> RecordingGeometry {
        RecordingGeometry(target: target, recordingRect: globalRect, windowFrames: windowFrames, size: size)
    }
}
