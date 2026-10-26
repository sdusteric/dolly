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

    func stop() throws {
        stopped = true
        guard let url else { return }
        let writer = try PointerLogWriter(url: url)
        samples.forEach(writer.append)
        try writer.close()
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
        pointer.samples = makeLog(presses: [(2.4, 2.49, 500, 500)], until: 3)
        let clock = FakeClock()
        let c = controller(source: FakeRecordingSource(options: .init(seconds: 3)), pointer: pointer, clock: clock)
        await c.start(plan: plan)
        #expect(clock.sleeps == [1, 1, 1])
        #expect(c.countdownSeen == [3, 2, 1])
        guard case .recording = c.state else { Issue.record("not recording: \(c.state)"); return }
        let take = try #require(await c.requestStop(hostTime: 3.0))
        #expect(take.zooms.count == 1)
        #expect(take.recordingRect == CGRect(x: 0, y: 0, width: 1440, height: 900))
        #expect(approx(take.duration, 3.0, tol: 0.05))
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

    @Test func secondTakeIsNumberedTwo() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        for expected in ["Untitled take 1", "Untitled take 2"] {
            let c = controller(source: FakeRecordingSource(options: .init(seconds: 1)), pointer: FakePointerSampler())
            await c.start(plan: plan)
            #expect(try #require(await c.requestStop(hostTime: 1.0)).name == expected)
        }
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
