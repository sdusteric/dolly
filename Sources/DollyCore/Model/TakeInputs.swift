import CoreGraphics
import Foundation

extension Take {
    public func geometry(windowFrames: [WindowFrameSample]) -> RecordingGeometry {
        RecordingGeometry(target: target, recordingRect: recordingRect ?? CGRect(origin: .zero, size: size),
                          windowFrames: windowFrames, size: size)
    }
}

/// Reads a take folder's pointer and window logs back into what the editor, preview and export use.
public enum TakeInputs {
    /// Nil when the take has no readable pointer log; the take then plays without a drawn pointer.
    public static func pointerPath(take: Take, folder: URL) -> PointerPath? {
        let pointerURL = folder.appending(path: TakeStore.pointerName)
        guard FileManager.default.fileExists(atPath: pointerURL.path(percentEncoded: false)) else { return nil }
        let samples: [PointerSample]
        do {
            samples = try PointerLog.read(pointerURL)
        } catch {
            return nil
        }
        let windowURL = folder.appending(path: TakeStore.windowName)
        var frames: [WindowFrameSample] = []
        if take.target == .window, FileManager.default.fileExists(atPath: windowURL.path(percentEncoded: false)) {
            frames = (try? WindowFrameLog.read(windowURL)) ?? []
        }
        let geometry = take.geometry(windowFrames: frames)
        // Recording stops roughly at the last frame, so clicks on Stop are dropped again.
        let clicks = ClickDetector.clicks(from: samples, geometry: geometry, recordingStartHost: take.recordingStartHost,
                                          stopRequestHost: take.recordingStartHost + take.duration)
        return PointerPath(samples: samples, geometry: geometry, clicks: clicks,
                           recordingStartHost: take.recordingStartHost, look: take.look)
    }
}
