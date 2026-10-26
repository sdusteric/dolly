import AppKit
import DollyCore
import DollyRender
import DollySystem
import DollyUI
import SwiftUI

/// Record bar, area picker, countdown, menu bar timer and permission window around the
/// RecordingController (spec 4). Owned by the app delegate; never created in shot mode or tests.
@MainActor
final class RecordingWiring {
    let controller: RecordingController
    var onTake: (Take) -> Void = { _ in }

    private let settings: DollyCore.Settings
    private let shortcut: String
    private let areaPicker = AreaPicker()
    private var barPanel: NSPanel?
    private var countdownPanel: NSPanel?
    private var permissionWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var statusHost: NSHostingView<StatusTimerView>?
    private var ticker: Timer?
    private var startedAt = Date()
    private var bar = RecordBarModel()
    private var windows: [PickableWindow] = []

    init(paths: DollyPaths, settings: DollyCore.Settings) {
        self.settings = settings
        shortcut = settings.hotkey.displayString
        controller = RecordingController(
            store: TakeStore(paths: paths), source: LiveRecordingSource(),
            pointer: PointerSampler(clickSource: settings.advanced.clickSource, pointerShapes: settings.advanced.pointerShapes),
            clock: HostClock(), disk: LiveDiskSpace(), rules: ZoomRules(), namer: ZoomNamer()
        )
    }

    func hotkeyPressed() {
        switch RecordBarModel.hotkey(in: controller.state) {
        case .openBar: openBar()
        case .stop: Task { await stop() }
        case .cancelCountdown: controller.cancelCountdown()
        case .ignore: break
        }
    }

    func openBar() {
        guard PermissionProbe.preflight() else { return showPermission(denied: false) }
        Task {
            windows = await WindowCatalog.windows()
            showBar()
        }
    }

    // MARK: Record bar

    private func showBar() {
        barPanel?.orderOut(nil)
        let binding = Binding(get: { self.bar }, set: { self.bar = $0; self.showBar() })
        let view = RecordBar(model: binding, windows: windows, shortcut: shortcut,
                             record: { [weak self] in self?.record() }, cancel: { [weak self] in self?.closeBar() })
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let panel = barPanel ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.setFrame(CGRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height - 24, width: size.width, height: size.height), display: true)
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.makeKeyAndOrderFront(nil)
        barPanel = panel
    }

    private func closeBar() {
        barPanel?.orderOut(nil)
        barPanel = nil
    }

    private func record() {
        closeBar()
        switch bar.target {
        case .display:
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
            guard let screen else { return }
            begin(target: .display, displayID: screen.displayID, windowID: nil, rect: screen.frame, scale: screen.backingScaleFactor)
        case .window:
            guard let window = windows.first(where: { $0.id == bar.windowID }) else { return }
            let scale = NSScreen.screens.first { $0.displayID == window.displayID }?.backingScaleFactor ?? 2
            begin(target: .window, displayID: window.displayID, windowID: window.id, rect: window.frame, scale: scale)
        case .area:
            areaPicker.pick { [weak self] rect, screen in
                guard let self, let rect, let screen else { return }
                begin(target: .area, displayID: screen.displayID, windowID: nil, rect: rect, scale: screen.backingScaleFactor)
            }
        }
    }

    private func begin(target: TargetKind, displayID: UInt32, windowID: UInt32?, rect: CGRect, scale: Double) {
        guard let plan = try? RecordingPlan.make(target: target, displayID: displayID, windowID: windowID, globalRect: rect, scale: scale) else {
            NSSound.beep()
            return
        }
        showCountdown(over: rect)
        Task {
            await controller.start(plan: plan)
            countdownPanel?.orderOut(nil)
            countdownPanel = nil
            if case .recording = controller.state { showStatusTimer() }
            if case .failed(let message) = controller.state, message == RecordingController.couldNotStartMessage,
               !PermissionProbe.preflight() {
                showPermission(denied: true)
            }
        }
    }

    // MARK: Countdown and timer

    private func showCountdown(over rect: CGRect) {
        let panel = NSPanel(contentRect: CGRect(x: rect.midX - 60, y: rect.midY - 60, width: 120, height: 120),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = NSHostingView(rootView: CountdownHost(controller: controller))
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        countdownPanel = panel
    }

    private func showStatusTimer() {
        startedAt = Date()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let host = NSHostingView(rootView: StatusTimerView(elapsed: 0))
        host.frame = CGRect(origin: CGPoint(x: 2, y: 2), size: host.fittingSize)
        item.button?.addSubview(host)
        item.button?.frame.size.width = host.fittingSize.width + 4
        item.length = host.fittingSize.width + 4
        item.button?.target = self
        item.button?.action = #selector(stopClicked)
        item.button?.toolTip = RecordBarModel.tooltip(elapsed: 0, shortcut: shortcut)
        statusItem = item
        statusHost = host
        var seconds = 0
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                seconds += 1
                let elapsed = Date().timeIntervalSince(self.startedAt)
                self.statusHost?.rootView = StatusTimerView(elapsed: elapsed)
                self.statusItem?.button?.toolTip = RecordBarModel.tooltip(elapsed: elapsed, shortcut: self.shortcut)
                if seconds % 5 == 0 {
                    Task {
                        await self.controller.tick(hostTime: HostClock().now())
                        if case .recording = self.controller.state {} else { self.finishTimer() }
                    }
                }
            }
        }
    }

    @objc private func stopClicked() { Task { await stop() } }

    private func stop() async {
        let take = await controller.requestStop(hostTime: HostClock().now())
        finishTimer()
        if let take { onTake(take) }
    }

    private func finishTimer() {
        ticker?.invalidate()
        ticker = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        statusHost = nil
        if let take = controller.lastTake, !take.notes.isEmpty { onTake(take) }
    }

    // MARK: Permission

    private func showPermission(denied: Bool) {
        let view = PermissionWindowView(denied: denied, allow: { PermissionProbe.requestOnce() }, openSettings: {
            if let url = PermissionProbe.screenRecordingSettingsURL { NSWorkspace.shared.open(url) }
        })
        let window = permissionWindow ?? NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = PermissionWindowModel.title
        window.contentView = NSHostingView(rootView: view)
        window.setContentSize(window.contentView?.fittingSize ?? CGSize(width: 440, height: 200))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        permissionWindow = window
    }
}

/// Shows the controller's countdown number while it counts.
private struct CountdownHost: View {
    let controller: RecordingController
    var body: some View {
        if case .countdown(let n) = controller.state { CountdownView(number: n) } else { Color.clear }
    }
}
