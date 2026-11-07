import CoreGraphics
import Foundation
import Testing
@testable import DollyCore

/// Writes a prepared log when the controller starts sampling, the way PointerSampler would.
final class FakePointerSampler: PointerSampling, @unchecked Sendable {
    var samples: [PointerSample] = []
    private(set) var started = false
    private(set) var stopped = false
    private var url: URL?

    func start(pointerURL: URL, windowLogURL: URL?, windowID: UInt32?) throws {
        started = true
        url = pointerURL
    }

    var failsToStop = false

    func stop() throws {
        stopped = true
        if failsToStop { throw CocoaError(.fileWriteUnknown) }
        guard let url else { return }
        let writer = try PointerLogWriter(url: url)
        samples.forEach(writer.append)
        try writer.close()
    }
}

/// Answers only once the test opens it, like Vision loading its models.
final class GatedNamer: ZoomNaming, @unchecked Sendable {
    private let lock = NSLock()
    private var answer: String?
    private var waiting: [CheckedContinuation<String, Never>] = []

    func name(for click: Click, movie: URL, take: Take) async -> String {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let answer { lock.unlock(); continuation.resume(returning: answer) } else { waiting.append(continuation); lock.unlock() }
        }
    }

    func open(_ name: String) {
        lock.lock()
        answer = name
        let pending = waiting
        waiting = []
        lock.unlock()
        pending.forEach { $0.resume(returning: name) }
    }
}

@MainActor @Suite struct RecordingControllerTests {
    let home = tempURL("home")
    var store: TakeStore { TakeStore(paths: DollyPaths(environment: ["DOLLY_HOME": home.path])) }
    let plan = try! RecordingPlan.make(target: .display, displayID: 1, windowID: nil,
                                       globalRect: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 1, pixelSize: PixelSize(width: 320, height: 200))

    func controller(source: FakeRecordingSource, pointer: FakePointerSampler, disk: FakeDiskSpace = FakeDiskSpace(bytes: 50_000_000_000),
                    clock: FakeClock = FakeClock()) -> RecordingController {
        RecordingController(store: store, source: source, pointer: pointer, clock: clock, disk: disk, rules: ZoomRules())
    }

    @Test func countdownThenRecordsThenSavesTake() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let pointer = FakePointerSampler()
        // 4 s, so the click at 2.4 s has room to move in, hold and move out before the end.
        pointer.samples = makeLog(presses: [(2.4, 2.49, 500, 500)], until: 4)
        let clock = FakeClock()
        let c = controller(source: FakeRecordingSource(options: .init(seconds: 4)), pointer: pointer, clock: clock)
        await c.start(plan: plan)
        #expect(clock.sleeps == [1, 1, 1])
        #expect(c.countdownSeen == [3, 2, 1])
        guard case .recording = c.state else { Issue.record("not recording: \(c.state)"); return }
        let take = try #require(await c.requestStop(hostTime: 4.0))
        #expect(take.zooms.count == 1)
        #expect(take.recordingRect == CGRect(x: 0, y: 0, width: 1440, height: 900))
        #expect(approx(take.duration, 4.0, tol: 0.05))
        #expect(take.name == "Untitled take 1")
        #expect(pointer.started && pointer.stopped)
        #expect(FileManager.default.fileExists(atPath: store.folder(for: take.id).appending(path: TakeStore.jsonName).path))
        #expect(c.state == .idle)
    }

    @Test func refusesUnderTwoGigabytes() async {
        defer { try? FileManager.default.removeItem(at: home) }
        let c = controller(source: FakeRecordingSource(options: .init(seconds: 3)), pointer: FakePointerSampler(),
                           disk: FakeDiskSpace(bytes: 1_900_000_000))
        await c.start(plan: plan)
        #expect(c.state == .failed("Not enough disk space to record"))
    }

    @Test func stopsWhenDiskRunsLow() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let disk = FakeDiskSpace(bytes: 50_000_000_000)
        let c = controller(source: FakeRecordingSource(options: .init(seconds: 3)), pointer: FakePointerSampler(), disk: disk)
        await c.start(plan: plan)
        disk.bytes = 400_000_000
        await c.tick(hostTime: 2.0)
        #expect(c.state == .idle)
        #expect(c.lastTake?.notes == ["Stopped: disk almost full"])
    }

    @Test func stopClickMakesNoZoom() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let pointer = FakePointerSampler()
        pointer.samples = makeLog(presses: [(2.9, 2.98, 500, 500)], until: 3)
        let c = controller(source: FakeRecordingSource(options: .init(seconds: 3)), pointer: pointer)
        await c.start(plan: plan)
        #expect(try #require(await c.requestStop(hostTime: 3.0)).zooms.isEmpty)
    }

    @Test func sourceFailureFailsWithItsMessage() async {
        defer { try? FileManager.default.removeItem(at: home) }
        let c = controller(source: FakeRecordingSource(options: .init(seconds: 3, failOnStart: true)), pointer: FakePointerSampler())
        await c.start(plan: plan)
        #expect(c.state == .failed("Recording could not start"))
    }

    /// Review finding 3: a failed start leaves no empty folder behind as a broken sidebar row.
    @Test func failedStartLeavesNoFolder() async {
        defer { try? FileManager.default.removeItem(at: home) }
        let c = controller(source: FakeRecordingSource(options: .init(seconds: 3, failOnStart: true)), pointer: FakePointerSampler())
        await c.start(plan: plan)
        #expect(store.list().isEmpty)
    }

    /// Review finding 2: the stream stopping on its own (window closed) saves the take with a note.
    @Test func streamStopEventSavesTakeWithNote() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let source = FakeRecordingSource(options: .init(seconds: 1, stopEvent: .windowClosed))
        let c = controller(source: source, pointer: FakePointerSampler())
        await c.start(plan: plan)
        for _ in 0..<400 where c.state != .idle { try await Task.sleep(for: .milliseconds(10)) }
        #expect(c.state == .idle)
        #expect(c.lastTake?.notes == ["Stopped: the window closed"])
    }

    /// Review finding 4: a pointer log that fails to close still stops the screen and keeps the take.
    @Test func pointerStopFailureStillStopsSourceAndSavesTake() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let pointer = FakePointerSampler()
        pointer.failsToStop = true
        let source = FakeRecordingSource(options: .init(seconds: 1))
        let c = controller(source: source, pointer: pointer)
        await c.start(plan: plan)
        let take = try #require(await c.requestStop(hostTime: 1.0))
        #expect(source.stopped)
        #expect(take.notes == [RecordingController.pointerLogNote])
        #expect(c.state == .idle)
    }

    @Test func secondTakeIsNumberedTwo() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        for expected in ["Untitled take 1", "Untitled take 2"] {
            let c = controller(source: FakeRecordingSource(options: .init(seconds: 1)), pointer: FakePointerSampler())
            await c.start(plan: plan)
            #expect(try #require(await c.requestStop(hostTime: 1.0)).name == expected)
        }
    }

    /// The take is named after what was recorded, with a number when that name is taken.
    @Test func takeIsNamedFromThePlanHint() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        var named = plan
        named.nameHint = "Kalos, apple.com"
        for expected in ["Kalos, apple.com", "Kalos, apple.com 2"] {
            let c = controller(source: FakeRecordingSource(options: .init(seconds: 1)), pointer: FakePointerSampler())
            await c.start(plan: named)
            #expect(try #require(await c.requestStop(hostTime: 1.0)).name == expected)
        }
    }

    /// Reading the screen for zoom names can take many seconds (Vision loads its models on first
    /// use), so the take is saved and handed over first, with the placeholder names.
    @Test func takeIsSavedWithoutWaitingForZoomNames() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let pointer = FakePointerSampler()
        pointer.samples = makeLog(presses: [(2.4, 2.49, 500, 500)], until: 4)
        let namer = GatedNamer()
        let c = RecordingController(store: store, source: FakeRecordingSource(options: .init(seconds: 4)), pointer: pointer,
                                    clock: FakeClock(), disk: FakeDiskSpace(bytes: 50_000_000_000), rules: ZoomRules(), namer: namer)
        var updates: [ZoomNameUpdate] = []
        c.onZoomNames = { _, names in updates = names }
        await c.start(plan: plan)
        let take = try #require(await c.requestStop(hostTime: 4.0))
        let zoom = try #require(take.zooms.first)
        #expect(zoom.name.hasPrefix("Click at"))
        #expect(try store.load(store.folder(for: take.id)).zooms.first?.name == zoom.name)
        #expect(c.state == .idle && updates.isEmpty)
        namer.open("Run check up")
        for _ in 0..<200 where updates.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(updates == [ZoomNameUpdate(id: zoom.id, from: zoom.name, to: "Run check up")])
    }

    /// Quit while a Stop is still saving waits for that save and gets the same take, so the app
    /// never terminates before take.json is written.
    @Test func secondStopWaitsForTheFirst() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let c = controller(source: FakeRecordingSource(options: .init(seconds: 2)), pointer: FakePointerSampler())
        await c.start(plan: plan)
        async let first = c.requestStop(hostTime: 2)
        async let quit = c.stop(hostTime: 2.1, reason: .quit)
        let (a, b) = await (first, quit)
        let take = try #require(a)
        #expect(b?.id == take.id)
        #expect(try store.load(store.folder(for: take.id)).id == take.id)
    }

    func sideController(camera: FakeSideSource?, microphone: FakeSideSource? = nil) -> RecordingController {
        let c = RecordingController(store: store, source: FakeRecordingSource(options: .init(seconds: 1, startHost: 100)),
                            pointer: FakePointerSampler(), clock: FakeClock(), disk: FakeDiskSpace(bytes: 50_000_000_000),
                            rules: ZoomRules(), camera: camera, microphone: microphone)
        camera?.report = { [weak c] in c.map { if case .recording = $0.state { "recording" } else { "\($0.state)" } } ?? "" }
        return c
    }

    var sidePlan: RecordingPlan {
        var p = plan
        p.cameraID = "cam-1"
        p.microphoneID = "mic-1"
        return p
    }

    @Test func cameraOffsetComesFromFirstSample() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let camera = FakeSideSource(firstHost: 100.25), microphone = FakeSideSource(firstHost: 99.9)
        let c = sideController(camera: camera, microphone: microphone)
        await c.start(plan: sidePlan)
        let take = try #require(await c.requestStop(hostTime: 101))
        #expect(approx(try #require(take.camera).startOffset, 0.25))
        #expect(approx(try #require(take.microphoneOffset), -0.1))
        #expect(camera.deviceID == "cam-1" && microphone.deviceID == "mic-1")
        #expect(camera.stopped && microphone.stopped)
        let folder = store.folder(for: take.id)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "camera.mov").path))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: TakeStore.audioName).path))
        #expect(take.notes.isEmpty)
    }

    @Test func noSwitchesNoSideFiles() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let camera = FakeSideSource(firstHost: 100)
        let c = sideController(camera: camera, microphone: FakeSideSource(firstHost: 100))
        await c.start(plan: plan)
        let take = try #require(await c.requestStop(hostTime: 101))
        #expect(take.camera == nil && take.microphoneOffset == nil)
        #expect(!camera.started)
        let names = try FileManager.default.contentsOfDirectory(atPath: store.folder(for: take.id).path)
        #expect(!names.contains("camera.mov") && !names.contains(TakeStore.audioName))
    }

    @Test func sideSourceFailureKeepsScreenTake() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let camera = FakeSideSource(firstHost: 100.1, failsAtHost: 121.4)
        let c = sideController(camera: camera)
        await c.start(plan: sidePlan)
        await Task.yield()
        let take = try #require(await c.requestStop(hostTime: 125))
        #expect(take.notes.contains("The camera stopped at 0:21.4"))
        #expect(take.camera != nil)
    }

    /// Review finding 2: a camera that fails to start is told to stop, so it never stays open.
    @Test func sideSourceThatCannotStartIsStopped() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let camera = FakeSideSource(firstHost: 100, failsToStart: true)
        let c = sideController(camera: camera)
        await c.start(plan: sidePlan)
        #expect(camera.stopped)
        _ = await c.requestStop(hostTime: 101)
    }

    /// Review finding 3: the camera and microphone open together, after the screen is recording.
    @Test func sidesStartTogetherWhileRecording() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let microphone = FakeSideSource(firstHost: 100)
        let camera = FakeSideSource(firstHost: 100.2, waitsFor: microphone)
        let c = sideController(camera: camera, microphone: microphone)
        await c.start(plan: sidePlan)
        let take = try #require(await c.requestStop(hostTime: 101))
        #expect(camera.sawPeerStart)
        #expect(camera.stateAtStart == "recording")
        #expect(take.camera != nil && take.microphoneOffset != nil)
    }

    @Test func sideSourceThatCannotStartIsDropped() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let c = sideController(camera: FakeSideSource(firstHost: 100, failsToStart: true), microphone: FakeSideSource(firstHost: 100))
        await c.start(plan: sidePlan)
        guard case .recording = c.state else { Issue.record("not recording: \(c.state)"); return }
        let take = try #require(await c.requestStop(hostTime: 101))
        #expect(take.notes == ["The camera did not start"])
        #expect(take.camera == nil && take.microphoneOffset != nil)
    }
}

/// Cancels the countdown from inside the first sleep, the way the hotkey would.
final class CancellingClock: DollyClock, @unchecked Sendable {
    weak var controller: RecordingController?
    func now() -> Double { 0 }
    func sleep(seconds: Double) async { await MainActor.run { controller?.cancelCountdown() } }
}

@Suite struct CountdownCancelTests {
    @MainActor @Test func cancellingTheCountdownRecordsNothing() async throws {
        let home = tempURL("home")
        defer { try? FileManager.default.removeItem(at: home) }
        let store = TakeStore(paths: DollyPaths(environment: ["DOLLY_HOME": home.path]))
        let clock = CancellingClock()
        let pointer = FakePointerSampler()
        let c = RecordingController(store: store, source: FakeRecordingSource(options: .init(seconds: 1)), pointer: pointer,
                                    clock: clock, disk: FakeDiskSpace(bytes: 50_000_000_000), rules: ZoomRules())
        clock.controller = c
        let plan = try RecordingPlan.make(target: .display, displayID: 1, windowID: nil,
                                          globalRect: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 1, pixelSize: PixelSize(width: 320, height: 200))
        await c.start(plan: plan)
        #expect(c.state == .idle)
        #expect(!pointer.started)
        #expect(store.list().isEmpty)
    }
}
