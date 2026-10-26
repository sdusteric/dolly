import Foundation
import Observation

/// Countdown, recording and saving a take (spec 4 and 5.1). The app calls `tick` every 5 s while
/// recording for the disk and length checks.
@MainActor
@Observable
public final class RecordingController {
    nonisolated public enum State: Hashable, Sendable {
        case idle, countdown(Int), recording(since: Double), finishing, failed(String)
    }

    public static let countdownFrom = 3
    public static let noDiskMessage = "Not enough disk space to record"
    public static let couldNotStartMessage = "Recording could not start"

    public private(set) var state: State = .idle
    public private(set) var countdownSeen: [Int] = []
    public private(set) var lastTake: Take?

    @ObservationIgnored private let store: TakeStore
    @ObservationIgnored private let source: any RecordingSource
    @ObservationIgnored private let pointer: any PointerSampling
    @ObservationIgnored private let clock: any DollyClock
    @ObservationIgnored private let disk: any DiskSpaceProbing
    @ObservationIgnored private let rules: ZoomRules
    @ObservationIgnored private let namer: any ZoomNaming
    @ObservationIgnored private var plan: RecordingPlan?
    @ObservationIgnored private var takeID: UUID?
    @ObservationIgnored private var startHost: Double?
    @ObservationIgnored private var cancelled = false

    public init(store: TakeStore, source: any RecordingSource, pointer: any PointerSampling, clock: any DollyClock,
                disk: any DiskSpaceProbing, rules: ZoomRules, namer: any ZoomNaming = FallbackZoomNamer()) {
        self.store = store
        self.source = source
        self.pointer = pointer
        self.clock = clock
        self.disk = disk
        self.rules = rules
        self.namer = namer
    }

    public func start(plan: RecordingPlan) async {
        guard state == .idle || isFailed else { return }
        let free = disk.freeBytes(at: store.paths.takesFolder) ?? .max
        guard free >= DiskLimits.startBytes else {
            state = .failed(Self.noDiskMessage)
            return
        }
        countdownSeen = []
        cancelled = false
        for n in stride(from: Self.countdownFrom, through: 1, by: -1) {
            state = .countdown(n)
            countdownSeen.append(n)
            await clock.sleep(seconds: 1)
            if cancelled {
                state = .idle
                return
            }
        }
        let id = UUID()
        do {
            let folder = try store.createFolder(for: id)
            try pointer.start(pointerURL: folder.appending(path: TakeStore.pointerName),
                              windowLogURL: plan.target == .window ? folder.appending(path: TakeStore.windowName) : nil,
                              windowID: plan.windowID)
            try await source.start(plan: plan, movieURL: folder.appending(path: TakeStore.movieName)) { _ in }
        } catch {
            try? pointer.stop()
            state = .failed(Self.couldNotStartMessage)
            return
        }
        self.plan = plan
        takeID = id
        state = .recording(since: clock.now())
    }

    /// The hotkey during 3, 2, 1: nothing is recorded.
    public func cancelCountdown() {
        if case .countdown = state { cancelled = true }
    }

    /// Disk and length checks while recording; stops with a note when either runs out.
    public func tick(hostTime: Double) async {
        guard case .recording(let since) = state else { return }
        if (disk.freeBytes(at: store.paths.takesFolder) ?? .max) < DiskLimits.stopBytes {
            await stop(hostTime: hostTime, reason: .diskFull)
        } else if hostTime - since >= RecordingPlan.maxSeconds {
            await stop(hostTime: hostTime, reason: .maxLength)
        }
    }

    public func requestStop(hostTime: Double) async -> Take? {
        await stop(hostTime: hostTime, reason: .user)
    }

    @discardableResult
    private func stop(hostTime: Double, reason: RecordingStopReason) async -> Take? {
        guard case .recording = state, let plan, let id = takeID else { return nil }
        state = .finishing
        defer {
            self.plan = nil
            takeID = nil
        }
        let folder = store.folder(for: id)
        do {
            try pointer.stop()
            let result = try await source.stop()
            let samples = (try? PointerLog.read(folder.appending(path: TakeStore.pointerName))) ?? []
            let frames = (try? WindowFrameLog.read(folder.appending(path: TakeStore.windowName))) ?? []
            let clicks = ClickDetector.clicks(from: samples, geometry: plan.geometry(windowFrames: frames),
                                              recordingStartHost: result.startHost, stopRequestHost: hostTime)
            var take = Take(id: id, name: nextName(), created: Date(), target: plan.target, size: plan.size,
                            pixelScale: plan.scale, fps: plan.fps, duration: result.duration,
                            recordingStartHost: result.startHost, notes: reason.note.map { [$0] } ?? [])
            take.recordingRect = plan.globalRect
            take.zooms = rules.zooms(for: clicks, size: plan.size, target: plan.target, trim: take.trim)
            let movie = folder.appending(path: TakeStore.movieName)
            for (i, zoom) in take.zooms.enumerated() {
                if let first = zoom.clickIDs.first, let click = clicks.first(where: { $0.id == first }) {
                    take.zooms[i].name = await namer.name(for: click, movie: movie, take: take)
                }
            }
            try store.save(take)
            lastTake = take
            state = .idle
            return take
        } catch {
            state = .failed("Stopped: the recording failed")
            return nil
        }
    }

    private var isFailed: Bool { if case .failed = state { true } else { false } }

    private func nextName() -> String {
        let used = Set(store.list().compactMap { entry -> String? in
            if case .ok(let take, _) = entry { take.name } else { nil }
        })
        var n = 1
        while used.contains("Untitled take \(n)") { n += 1 }
        return "Untitled take \(n)"
    }
}
