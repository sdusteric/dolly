import CoreGraphics
import Foundation

public enum TargetKind: String, Codable, Sendable { case window, area, display }

public struct PixelSize: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct ExportRecord: Codable, Hashable, Sendable {
    public var shape: ShapePreset
    public var url: URL
    public var date: Date
    public init(shape: ShapePreset, url: URL, date: Date) {
        self.shape = shape
        self.url = url
        self.date = date
    }
}

/// `take.json` (spec section 8). Version 1.
public struct Take: Codable, Hashable, Identifiable, Sendable {
    public var version = 1
    public var id: UUID
    public var name: String
    public var created: Date
    public var target: TargetKind
    /// The recorded content in points.
    public var size: CGSize
    /// The recorded content in global points when recording started; maps the pointer log into the
    /// take. Nil means the origin, which is what a window take needs (its log is window.bin).
    public var recordingRect: CGRect?
    public var pixelScale: Double
    public var fps: Int
    public var duration: Double
    public var trim: ClosedRange<Double>
    public var look: Look
    public var zooms: [Zoom]
    public var exports: [ExportRecord]
    /// Host clock seconds of the first frame; pointer log times are relative to it.
    public var recordingStartHost: Double
    public var notes: [String]
    /// The shape the stage last showed; nil (every M1 take) reads as 16:9.
    public var shape: ShapePreset?

    /// The webcam, when one was recorded.
    public var camera: CameraTrack?

    public var captions: CaptionTrack?
    /// `audio.m4a` time 0 is this many seconds into the take; nil when no microphone was recorded.
    public var microphoneOffset: Double?

    public var currentShape: ShapePreset { shape ?? .wide16x9 }

    public init(
        id: UUID = UUID(), name: String, created: Date = Date(), target: TargetKind, size: CGSize,
        pixelScale: Double, fps: Int, duration: Double, trim: ClosedRange<Double>? = nil,
        look: Look = Look(), zooms: [Zoom] = [], exports: [ExportRecord] = [],
        recordingStartHost: Double = 0, notes: [String] = []
    ) {
        self.id = id
        self.name = name
        self.created = created
        self.target = target
        self.size = size
        self.pixelScale = pixelScale
        self.fps = fps
        self.duration = duration
        self.trim = trim ?? 0...duration
        self.look = look
        self.zooms = zooms
        self.exports = exports
        self.recordingStartHost = recordingStartHost
        self.notes = notes
    }
}
