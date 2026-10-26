import AppKit
import CoreMedia
import DollyCore
import Foundation
import ScreenCaptureKit

/// Records with ScreenCaptureKit into `MasterWriter` (spec 4.2): the real pointer hidden, frames
/// kept with their own timestamps. Never used by tests or tools; only the configuration builder is.
/// `@unchecked Sendable`: `state` is only read or written under `lock`.
public final class LiveRecordingSource: NSObject, RecordingSource, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private struct Frame: @unchecked Sendable {
        let buffer: CVReadOnlyPixelBuffer
        let time: CMTime
    }

    private struct State {
        var stream: SCStream?
        var continuation: AsyncStream<Frame>.Continuation?
        var consumer: Task<Void, any Error>?
        var firstPTS: CMTime?
        var lastPTS: CMTime?
        var events: (@Sendable (RecordingEvent) -> Void)?
        var fps = 60
    }

    private let lock = NSLock()
    private var state = State()
    private let queue = DispatchQueue(label: "dev.sdusteric.dolly.capture", qos: .userInitiated)

    override public init() { super.init() }

    /// The SCStream configuration for a plan. `displayFrame` is the recorded display in global
    /// points, for the area's display-local, top-left source rect.
    public static func streamConfiguration(for plan: RecordingPlan, displayFrame: CGRect) -> SCStreamConfiguration {
        let c = SCStreamConfiguration()
        c.width = plan.pixelSize.width
        c.height = plan.pixelSize.height
        if plan.target == .area {
            c.sourceRect = CGRect(x: plan.globalRect.minX - displayFrame.minX, y: displayFrame.maxY - plan.globalRect.maxY,
                                  width: plan.globalRect.width, height: plan.globalRect.height)
        }
        c.scalesToFit = plan.target == .window
        c.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(plan.fps))
        c.queueDepth = plan.queueDepth
        c.showsCursor = plan.showsCursor
        c.ignoreShadowsSingleWindow = true
        c.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        c.colorSpaceName = CGColorSpace.itur_709
        c.colorMatrix = CGDisplayStream.yCbCrMatrix_ITU_R_709_2
        c.captureDynamicRange = .SDR
        return c
    }

    public func start(plan: RecordingPlan, movieURL: URL, events: @escaping @Sendable (RecordingEvent) -> Void) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == plan.displayID }) ?? content.displays.first else {
            throw RecordingSourceError.couldNotStart("no display")
        }
        let filter: SCContentFilter
        if plan.target == .window {
            guard let window = content.windows.first(where: { $0.windowID == plan.windowID }) else {
                throw RecordingSourceError.couldNotStart("the window is no longer on screen")
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
        } else {
            let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        }
        let configuration = Self.streamConfiguration(for: plan, displayFrame: CGDisplayBounds(display.displayID).flippedToGlobal)
        let writer = try MasterWriter(url: movieURL, pixelSize: plan.pixelSize, fps: plan.fps, realTime: true)
        let (frames, continuation) = AsyncStream<Frame>.makeStream(bufferingPolicy: .bufferingNewest(plan.queueDepth * 4))
        let consumer = Task {
            for await frame in frames { try await writer.append(frame.buffer, at: frame.time) }
            try await writer.finish()
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        lock.withLock { state = State(stream: stream, continuation: continuation, consumer: consumer, events: events, fps: plan.fps) }
        try await stream.startCapture()
    }

    public func stop() async throws -> RecordingResult {
        let (stream, continuation, consumer) = lock.withLock { (state.stream, state.continuation, state.consumer) }
        guard let stream, let consumer else { throw RecordingSourceError.notRecording }
        try? await stream.stopCapture()
        continuation?.finish()
        try await consumer.value
        return lock.withLock {
            let s = state
            let first = s.firstPTS?.seconds ?? 0, last = s.lastPTS?.seconds ?? first
            return RecordingResult(duration: last - first + 1 / Double(s.fps), startHost: first)
        }
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, Self.isComplete(sampleBuffer),
              let image = sampleBuffer.imageBuffer else { return }
        let pts = sampleBuffer.presentationTimeStamp
        lock.lock()
        let isFirst = state.firstPTS == nil
        if isFirst { state.firstPTS = pts }
        state.lastPTS = pts
        let first = state.firstPTS ?? pts, continuation = state.continuation, events = state.events
        lock.unlock()
        if isFirst { events?(.started(hostTime: pts.seconds)) }
        // ScreenCaptureKit hands over the buffer; the read-only wrapper keeps it alive for the writer.
        nonisolated(unsafe) let pixels = image
        continuation?.yield(Frame(buffer: CVReadOnlyPixelBuffer(unsafeBuffer: pixels), time: pts - first))
    }

    public func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let events = lock.withLock { state.events }
        let code = (error as NSError).code
        events?(.stopped(code == SCStreamError.Code.userStopped.rawValue ? .user : .streamFailed))
    }

    /// Only frames with new content; idle and blank status frames carry no image worth writing.
    static func isComplete(_ buffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }
}

extension CGRect {
    /// CoreGraphics display bounds are top-left of the main display; global points are bottom-left.
    var flippedToGlobal: CGRect {
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        return CGRect(x: minX, y: mainHeight - maxY, width: width, height: height)
    }
}
