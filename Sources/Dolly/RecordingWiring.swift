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
    private(set) var controller: RecordingController
    var onTake: (Take) -> Void = { _ in }

    private let paths: DollyPaths
    private var settings: DollyCore.Settings
    private let shortcut: String
    private let areaPicker = AreaPicker()
    private var barPanel: KeyablePanel?
    private var sleepObserver: NSObjectProtocol?
    /// The Advanced switches the current controller was built with.
    private var builtAdvanced: DollyCore.Settings.Advanced
    private var countdownPanel: NSPanel?
    private var permissionWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var statusHost: NSHostingView<StatusTimerView>?
    private var ticker: Timer?
    private var startedAt = Date()
    private var bar = RecordBarModel()
    private var windows: [PickableWindow] = []

    init(paths: DollyPaths, settings: DollyCore.Settings) {
        self.paths = paths
        self.settings = settings
        shortcut = settings.hotkey.displayString
        controller = Self.makeController(paths: paths, settings: settings)
        builtAdvanced = settings.advanced
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopNow(reason: .sleep) }
        }
    }

    private static func makeController(paths: DollyPaths, settings: DollyCore.Settings) -> RecordingController {
        RecordingController(
            store: TakeStore(paths: paths), source: LiveRecordingSource(),
            pointer: PointerSampler(clickSource: settings.advanced.clickSource, pointerShapes: settings.advanced.pointerShapes),
            clock: HostClock(), disk: LiveDiskSpace(), rules: ZoomRules(), namer: ZoomNamer()
        )
    }

    /// New Advanced switches take effect at the next recording, never during one.
    func apply(_ settings: DollyCore.Settings) {
        self.settings = settings
        rebuildIfNeeded()
    }

    /// A change made while recording applies once the recording ends.
    private func rebuildIfNeeded() {
        guard settings.advanced != builtAdvanced else { return }
        switch controller.state {
        case .idle, .failed:
            controller = Self.makeController(paths: paths, settings: settings)
            builtAdvanced = settings.advanced
        default: break
        }
    }

    var currentFolder: URL? { controller.recordingFolder }

    var isRecording: Bool {
        switch controller.state {
        case .recording, .finishing: true
        default: false
        }
    }

    /// Quit: finish the take so it is not left without take.json.
    func stopForQuit() async {
        if case .recording = controller.state {
            await controller.stop(hostTime: HostClock().now(), reason: .quit)
        }
        finishTimer()
    }

    private func stopNow(reason: RecordingStopReason) {
        guard case .recording = controller.state else { return }
        Task {
            await controller.stop(hostTime: HostClock().now(), reason: reason)
            finishTimer()
        }
    }

    func hotkeyPressed() {
        switch RecordBarModel.hotkey(in: controller.state) {
        case .openBar: openBar()
        case .stop: Task { await stop() }
        case .cancelCountdown: controller.cancelCountdown()
        case .ignore: break
        }
    }

    private func openBar() {
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
        let panel = barPanel ?? KeyablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
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
        // The bar can stay open while a recording starts from the hotkey.
        switch controller.state {
        case .idle, .failed: break
        default: return
        }
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
            if case .failed(let message) = controller.state {
                if message == RecordingController.couldNotStartMessage, !PermissionProbe.preflight() {
                    showPermission(denied: true)
                } else {
                    showFailure(message)
                }
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
        guard statusItem == nil else { return }
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
                // A stream that stopped on its own shows within a second; disk and length every 5 s.
                let checkDisk = seconds % 5 == 0
                Task {
                    if checkDisk { await self.controller.tick(hostTime: HostClock().now()) }
                    switch self.controller.state {
                    case .recording, .finishing: break
                    default: self.finishTimer()
                    }
                }
            }
        }
    }

    @objc private func stopClicked() { Task { await stop() } }

    private func stop() async {
        let take = await controller.requestStop(hostTime: HostClock().now())
        // The 1 s ticker may have seen the stop first and already opened the take.
        guard statusItem != nil || ticker != nil else { return }
        clearTimer()
        if let take {
            onTake(take)
        } else if case .failed(let message) = controller.state {
            showFailure(message)
        }
    }

    /// The recording ended without the owner's stop (window closed, disk, length, sleep, an error):
    /// open the take it saved, or say why there is none.
    private func finishTimer() {
        guard statusItem != nil || ticker != nil else { return rebuildIfNeeded() }
        clearTimer()
        switch controller.state {
        case .failed(let message): showFailure(message)
        default: if let take = controller.lastTake { onTake(take) }
        }
    }

    private func clearTimer() {
        ticker?.invalidate()
        ticker = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        statusHost = nil
        rebuildIfNeeded()
    }

    private func showFailure(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = message == RecordingController.noDiskMessage
            ? "Dolly needs 2 GB free to start a recording."
            : "If a take was started, its folder in ~/Movies/Dolly/Takes keeps what was recorded."
        NSApp.activate()
        alert.runModal()
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
