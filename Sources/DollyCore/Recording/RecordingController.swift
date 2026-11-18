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
    public static let stopFailedMessage = "Stopped: the recording failed"
    /// Kept on a take whose pointer log could not be closed; the movie is fine.
    public static let pointerLogNote = "Some pointer moves were not saved"
    public static let cameraFile = "camera.mov"

    /// The camera and the microphone, which record beside the screen and never stop it.
    nonisolated enum Side: String, Sendable { case camera, microphone }

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
    /// The take whose stream is being started, and the reason if that stream stopped before it was recording.
    @ObservationIgnored private var starting: UUID?
    @ObservationIgnored private var stoppedWhileStarting: RecordingStopReason?
    @ObservationIgnored private var startHost: Double?
    @ObservationIgnored private var cancelled = false
    @ObservationIgnored private let sides: [Side: any SideSource]
    /// Host time of each running side's first sample.
    @ObservationIgnored private var sideStarts: [Side: Double] = [:]
    @ObservationIgnored private var sideFailures: [Side: Double] = [:]
    @ObservationIgnored private var sideNotes: [String] = []
    @ObservationIgnored private var sideStartTask: Task<Void, Never>?
    @ObservationIgnored private var stopping: Task<Take?, Never>?
    /// Zoom names read from the screen, for the take with this id; arrives after the take is saved.
    @ObservationIgnored public var onZoomNames: (UUID, [ZoomNameUpdate]) -> Void = { _, _ in }

    public init(store: TakeStore, source: any RecordingSource, pointer: any PointerSampling, clock: any DollyClock,
                disk: any DiskSpaceProbing, rules: ZoomRules, namer: any ZoomNaming = FallbackZoomNamer(),
                camera: (any SideSource)? = nil, microphone: (any SideSource)? = nil) {
        self.store = store
        self.source = source
        self.pointer = pointer
        self.clock = clock
        self.disk = disk
        self.rules = rules
        self.namer = namer
        var sides: [Side: any SideSource] = [:]
        sides[.camera] = camera
        sides[.microphone] = microphone
        self.sides = sides
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
        let folder = store.folder(for: id)
        sideStarts = [:]
        sideFailures = [:]
        sideNotes = []
        do {
            _ = try store.createFolder(for: id)
            try pointer.start(pointerURL: folder.appending(path: TakeStore.pointerName),
                              windowLogURL: plan.target == .window ? folder.appending(path: TakeStore.windowName) : nil,
                              windowID: plan.windowID)
            starting = id
            stoppedWhileStarting = nil
            // The stream can stop on its own (window closed, display gone, an error): save the take then.
            try await source.start(plan: plan, movieURL: folder.appending(path: TakeStore.movieName)) { [weak self] event in
                guard case .stopped(let reason) = event else { return }
                Task { @MainActor in await self?.streamStopped(take: id, reason: reason) }
            }
        } catch {
            starting = nil
            try? pointer.stop()
            // An empty folder would list as a broken take.
            try? FileManager.default.removeItem(at: folder)
            state = .failed(Self.couldNotStartMessage)
            return
        }
        self.plan = plan
        takeID = id
        state = .recording(since: clock.now())
        starting = nil
        if let reason = stoppedWhileStarting {
            // Nothing more will come in: end it now and leave the camera and microphone closed.
            stoppedWhileStarting = nil
            await stop(hostTime: clock.now(), reason: reason)
            return
        }
        // The screen is recording; the camera and microphone open together beside it. One that
        // cannot start is stopped, noted and left out.
        let task = Task { await startSides(plan, folder: folder) }
        sideStartTask = task
        await task.value
    }

    /// The stream of `take` stopped on its own. One that is still starting ends as soon as it would
    /// have recorded; one from an earlier take says nothing about this one.
    private func streamStopped(take: UUID, reason: RecordingStopReason) async {
        if starting == take {
            stoppedWhileStarting = stoppedWhileStarting ?? reason
        } else if takeID == take {
            await stop(hostTime: clock.now(), reason: reason)
        }
    }

    private func startSides(_ plan: RecordingPlan, folder: URL) async {
        let wanted = [(Side.camera, plan.cameraID), (.microphone, plan.microphoneID)].compactMap { side, id in
            id.flatMap { id in sides[side].map { (side, id, $0) } }
        }
        let results = await withTaskGroup(of: (Side, Double?).self) { group in
            for (side, deviceID, device) in wanted {
                let url = folder.appending(path: side == .camera ? Self.cameraFile : TakeStore.audioName)
                group.addTask { [weak self] in
                    do {
                        let first = try await device.start(deviceID: deviceID, url: url) { failure in
                            Task { @MainActor in self?.sideFailures[side] = self?.sideFailures[side] ?? failure.hostTime }
                        }
                        return (side, first)
                    } catch {
                        try? await device.stop()
                        try? FileManager.default.removeItem(at: url)
                        return (side, nil)
                    }
                }
            }
            var collected: [(Side, Double?)] = []
            for await result in group { collected.append(result) }
            return collected
        }
        for (side, first) in results.sorted(by: { $0.0.rawValue < $1.0.rawValue }) {
            if let first { sideStarts[side] = first } else { sideNotes.append("The \(side.rawValue) did not start") }
        }
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

    /// Stops for `reason`; the app uses it for quit and sleep, the stream's events for the rest.
    /// A stop that comes while another is saving waits for it and returns the same take.
    @discardableResult
    public func stop(hostTime: Double, reason: RecordingStopReason) async -> Take? {
        if let stopping { return await stopping.value }
        guard case .recording = state, let plan, let id = takeID else { return nil }
        state = .finishing
        let task = Task { await finish(hostTime: hostTime, reason: reason, plan: plan, id: id) }
        stopping = task
        defer { stopping = nil }
        return await task.value
    }

    private func finish(hostTime: Double, reason: RecordingStopReason, plan: RecordingPlan, id: UUID) async -> Take? {
        defer {
            self.plan = nil
            takeID = nil
        }
        let folder = store.folder(for: id)
        // A stop that comes while the camera or microphone is still opening waits for it.
        await sideStartTask?.value
        sideStartTask = nil
        var notes = reason.note.map { [$0] } ?? []
        // The screen stops first, so a pointer log error can never leave it recording.
        let result: RecordingResult
        do {
            result = try await source.stop(atHostTime: hostTime)
        } catch {
            // take.mov keeps every fragment written so far; the folder lists as broken with Show in Finder.
            try? pointer.stop()
            for side in [Side.camera, .microphone] where sideStarts[side] != nil { try? await sides[side]?.stop() }
            state = .failed(Self.stopFailedMessage)
            return nil
        }
        do {
            try pointer.stop()
        } catch {
            notes.append(Self.pointerLogNote)
        }
        for side in [Side.camera, .microphone] where sideStarts[side] != nil {
            // The side file keeps what it wrote; a failing stop only loses its last moments.
            try? await sides[side]?.stop()
        }
        await Task.yield()
        notes += sideNotes
        for side in [Side.camera, .microphone] {
            if let failed = sideFailures[side] {
                notes.append("The \(side.rawValue) stopped at \(TimeText.clock(failed - result.startHost))")
            }
        }
        do {
            let samples = (try? PointerLog.read(folder.appending(path: TakeStore.pointerName))) ?? []
            let frames = (try? WindowFrameLog.read(folder.appending(path: TakeStore.windowName))) ?? []
            let clicks = ClickDetector.clicks(from: samples, geometry: plan.geometry(windowFrames: frames),
                                              recordingStartHost: result.startHost, stopRequestHost: hostTime)
            var take = Take(id: id, name: nextName(hint: plan.nameHint), created: Date(), target: plan.target, size: plan.size,
                            pixelScale: plan.scale, fps: plan.fps, duration: result.duration,
                            recordingStartHost: result.startHost, notes: notes)
            take.recordingRect = plan.globalRect
            if let first = sideStarts[.camera], FileManager.default.fileExists(atPath: folder.appending(path: Self.cameraFile).path(percentEncoded: false)) {
                take.camera = CameraTrack(startOffset: first - result.startHost)
            }
            if let first = result.systemAudioStart,
               FileManager.default.fileExists(atPath: folder.appending(path: TakeStore.systemAudioName).path(percentEncoded: false)) {
                take.systemAudioOffset = first - result.startHost
            }
            if let first = sideStarts[.microphone], FileManager.default.fileExists(atPath: folder.appending(path: TakeStore.audioName).path(percentEncoded: false)) {
                take.microphoneOffset = first - result.startHost
            }
            take.zooms = rules.zooms(for: clicks, size: plan.size, target: plan.target, trim: take.trim)
            try store.save(take)
            lastTake = take
            state = .idle
            nameZooms(take, clicks: clicks, movie: folder.appending(path: TakeStore.movieName))
            return take
        } catch {
            state = .failed(Self.stopFailedMessage)
            return nil
        }
    }

    /// The folder of the take being recorded, which has no take.json until it stops.
    public var recordingFolder: URL? { takeID.map(store.folder(for:)) }

    private var isFailed: Bool { if case .failed = state { true } else { false } }

    /// Reads each zoom's name from the screen after the take is saved. Vision can take many
    /// seconds the first time it runs, and the take must never wait on a label.
    private func nameZooms(_ take: Take, clicks: [Click], movie: URL) {
        let pending = take.zooms.compactMap { zoom in
            zoom.clickIDs.first.flatMap { id in clicks.first { $0.id == id } }.map { (zoom, $0) }
        }
        guard !pending.isEmpty else { return }
        let namer = namer, report = onZoomNames
        Task {
            var updates: [ZoomNameUpdate] = []
            for (zoom, click) in pending {
                updates.append(ZoomNameUpdate(id: zoom.id, from: zoom.name, to: await namer.name(for: click, movie: movie, take: take)))
            }
            report(take.id, updates)
        }
    }

    private func nextName(hint: String?) -> String {
        let used = Set(store.list().compactMap { entry -> String? in
            if case .ok(let take, _) = entry { take.name } else { nil }
        })
        return TakeName.unique(hint, used: used)
    }
}
