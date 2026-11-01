import AppKit
import CoreMedia
import DollyCore
import Foundation

/// Samples the pointer at 120 Hz on its own timer (spec 4.3 and 4.4), in global points on the host
/// clock ScreenCaptureKit stamps frames with. Clicks come from polling `pressedMouseButtons` unless
/// the owner switched to the event monitor (spike S1), which also catches taps shorter than one
/// sample. Needs no permission either way.
/// `@unchecked Sendable`: every field is behind `lock`; the timer, the monitor and stop meet there.
public final class PointerSampler: PointerSampling, @unchecked Sendable {
    public static let rate = 120.0
    /// The window frame is looked up every 4th sample (30 Hz): windows rarely move mid-take, and
    /// each lookup asks the window server for a list.
    static let windowEvery = 4

    private struct State {
        var timer: DispatchSourceTimer?
        var pointer: PointerLogWriter?
        var windows: WindowFrameLogWriter?
        var windowID: UInt32?
        var lastFrame: CGRect?
        var tick = 0
        var lastFlush = 0.0
        var monitorButtons = ButtonLatch()
        var monitor: Any?
    }

    private let lock = NSLock()
    private var state = State()
    private let queue = DispatchQueue(label: "dev.sdusteric.dolly.pointer", qos: .userInitiated)
    private let clickSource: Settings.ClickSource
    private let shapes: CursorShapeSampler?

    public init(clickSource: Settings.ClickSource, pointerShapes: Bool) {
        self.clickSource = clickSource
        shapes = pointerShapes ? CursorShapeSampler() : nil
    }

    static func hostNow() -> Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

    /// CGWindowList bounds are top-left of the main display; the logs use global bottom-left points.
    public static func globalFrame(windowListBounds r: CGRect, mainDisplayHeight: Double) -> CGRect {
        CGRect(x: r.minX, y: mainDisplayHeight - r.maxY, width: r.width, height: r.height)
    }

    public func start(pointerURL: URL, windowLogURL: URL?, windowID: UInt32?) throws {
        let pointer = try PointerLogWriter(url: pointerURL)
        let windows = try windowLogURL.map { try WindowFrameLogWriter(url: $0) }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1 / Self.rate, leeway: .microseconds(500))
        timer.setEventHandler { [weak self] in self?.sample() }
        lock.withLock { self.state = State(timer: timer, pointer: pointer, windows: windows, windowID: windowID) }
        if clickSource == .monitor { startMonitor() }
        shapes?.start()
        timer.resume()
    }

    public func stop() throws {
        shapes?.stop()
        lock.lock()
        let current = state
        state = State()
        lock.unlock()
        current.timer?.cancel()
        queue.sync {}
        if let monitor = current.monitor {
            // The monitor token is only touched on the main thread, where it was added.
            nonisolated(unsafe) let token = monitor
            DispatchQueue.main.async { NSEvent.removeMonitor(token) }
        }
        try current.pointer?.close()
        try current.windows?.close()
    }

    private func sample() {
        let t = Self.hostNow()
        let location = NSEvent.mouseLocation
        let shape = shapes?.current ?? .arrow
        let (windowID, tick) = lock.withLock {
            state.tick &+= 1
            return (state.windowID, state.tick)
        }
        let frame = windowID.flatMap { tick % Self.windowEvery == 1 ? Self.windowFrame($0) : nil }
        lock.withLock {
            let buttons = clickSource == .monitor ? self.state.monitorButtons.sample() : UInt8(truncatingIfNeeded: NSEvent.pressedMouseButtons & 3)
            let state = self.state
            state.pointer?.append(PointerSample(t: t, x: Float(location.x), y: Float(location.y), buttons: buttons, shape: shape))
            if state.windowID != nil, let frame, frame != state.lastFrame {
                state.windows?.append(WindowFrameSample(t: t, frame: frame))
                self.state.lastFrame = frame
            }
            if t - state.lastFlush >= 1 {
                // A failed flush is retried next second; close() reports the final one.
                try? state.pointer?.flush()
                try? state.windows?.flush()
                self.state.lastFlush = t
            }
        }
    }

    private static func windowFrame(_ id: UInt32) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(id)) as? [[String: Any]],
              let bounds = list.first?[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
        return globalFrame(windowListBounds: rect, mainDisplayHeight: CGDisplayBounds(CGMainDisplayID()).height)
    }

    /// Spike S1, plan A: a global monitor for mouse buttons. It must be added on the main thread.
    private func startMonitor() {
        DispatchQueue.main.async { [weak self] in
            let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]) { event in
                guard let self else { return }
                self.lock.withLock {
                    switch event.type {
                    case .leftMouseDown: self.state.monitorButtons.down(1)
                    case .leftMouseUp: self.state.monitorButtons.up(1)
                    case .rightMouseDown: self.state.monitorButtons.down(2)
                    case .rightMouseUp: self.state.monitorButtons.up(2)
                    default: break
                    }
                }
            }
            guard let self else { return }
            self.lock.withLock { self.state.monitor = monitor }
        }
    }
}
