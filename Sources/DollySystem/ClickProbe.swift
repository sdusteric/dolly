import AppKit
import DollyCore

/// The Advanced settings click test (spike S1): reports left clicks the same way the chosen click
/// source would see them while recording. Polling reads the button state at 120 Hz; the event
/// monitor adds a global monitor (other apps) and a local one (Dolly's own windows).
@MainActor
public final class ClickProbe {
    private var timer: Timer?
    private var monitors: [Any] = []
    private var wasDown = false

    public init() {}

    /// `onClick` gets the global point in AppKit coordinates (origin at the main display's bottom left).
    public func start(source: Settings.ClickSource, onClick: @escaping @MainActor (CGPoint) -> Void) {
        stop()
        switch source {
        case .poll:
            wasDown = NSEvent.pressedMouseButtons & 1 != 0
            timer = Timer.scheduledTimer(withTimeInterval: 1 / PointerSampler.rate, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let down = NSEvent.pressedMouseButtons & 1 != 0
                    if down, !self.wasDown { onClick(NSEvent.mouseLocation) }
                    self.wasDown = down
                }
            }
        case .monitor:
            if let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { _ in
                MainActor.assumeIsolated { onClick(NSEvent.mouseLocation) }
            }) {
                monitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { event in
                MainActor.assumeIsolated { onClick(NSEvent.mouseLocation) }
                return event
            }) {
                monitors.append(local)
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }
}
