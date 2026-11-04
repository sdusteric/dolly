import CoreGraphics
import Foundation
import Testing
@testable import DollyCore

@Suite struct PreviewInputsTests {
    func take() -> Take {
        var take = SyntheticTake.shelfDemo()
        take.zooms = [Zoom(start: 1, end: 3, aim: CGPoint(x: 100, y: 100), depth: 2, mode: .hold, moveIn: 0.6, moveOut: 0.5,
                           source: .auto, clickIDs: [], name: "")]
        return take
    }

    /// Look sliders, zoom aim and depth only change the video composition, so the player keeps its asset.
    @Test func lookAndZoomEditsKeepTheAsset() {
        let before = take()
        var after = before
        after.look.padding = 20
        after.look.shadow = 0.1
        after.zooms[0].aim = CGPoint(x: 300, y: 200)
        after.zooms[0].depth = 2.5
        after.shape = .square1x1
        after.name = "Renamed"
        #expect(after.compositionInputs == before.compositionInputs)
    }

    @Test func trimMicrophoneAndCameraTimingRebuildTheAsset() {
        let before = take()
        var trimmed = before
        trimmed.trim = 1...10
        var mic = before
        mic.microphoneOffset = 0.2
        var camera = before
        camera.camera = CameraTrack(startOffset: 0.1)
        var moved = camera
        moved.camera?.startOffset = 0.3
        #expect(trimmed.compositionInputs != before.compositionInputs)
        #expect(mic.compositionInputs != before.compositionInputs)
        #expect(camera.compositionInputs != before.compositionInputs)
        #expect(moved.compositionInputs != camera.compositionInputs)
    }

    /// Camera bubble looks are drawn by the compositor, not stored in the asset.
    @Test func cameraLookKeepsTheAsset() {
        var before = take()
        before.camera = CameraTrack(startOffset: 0.1)
        var after = before
        after.camera?.size = 0.3
        after.camera?.shown = false
        after.camera?.hidden = [2...3]
        #expect(after.compositionInputs == before.compositionInputs)
    }

    /// Aim mode shows the recording at 1x with the look, so dragging the aim or depth draws nothing new.
    @Test func aimStillIgnoresZoomEdits() {
        let before = take()
        var after = before
        after.zooms[0].aim = CGPoint(x: 300, y: 200)
        after.zooms[0].depth = 3
        after.trim = 2...20
        #expect(after.aimInputs == before.aimInputs)
    }

    @Test func aimStillFollowsLookAndShape() {
        let before = take()
        var look = before
        look.look.corners = 30
        var shape = before
        shape.shape = .tall9x16
        #expect(look.aimInputs != before.aimInputs)
        #expect(shape.aimInputs != before.aimInputs)
    }
}

/// A work function the test opens one input at a time.
private actor Gate {
    private(set) var started: [Int] = []
    private var waiting: [Int: CheckedContinuation<Void, Never>] = [:]
    private var opened: Set<Int> = []

    func pass(_ n: Int) async {
        started.append(n)
        if opened.contains(n) { return }
        await withCheckedContinuation { waiting[n] = $0 }
    }

    func open(_ n: Int) {
        opened.insert(n)
        waiting.removeValue(forKey: n)?.resume()
    }
}

@MainActor
private final class Delivered {
    var values: [Int] = []
}

@MainActor
private func until(_ condition: () async -> Bool) async {
    for _ in 0..<2000 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
}

@MainActor
@Suite struct LatestOnlyTests {
    /// While one render runs, only the newest request waits; the ones it replaced never run.
    @Test func runsTheNewestPendingRequestOnly() async {
        let gate = Gate()
        let delivered = Delivered()
        let work = LatestOnly<Int, Int>(work: { n in
            await gate.pass(n)
            return n * 10
        }, deliver: { delivered.values.append($0) })
        work.submit(1)
        work.submit(2)
        work.submit(3)
        await until { await gate.started == [1] }
        await gate.open(1)
        await until { await gate.started == [1, 3] }
        await gate.open(3)
        await until { delivered.values == [10, 30] }
        #expect(await gate.started == [1, 3])
        #expect(delivered.values == [10, 30])
        #expect(!work.isBusy)
    }

    /// After cancel the running result is dropped and nothing queued runs.
    @Test func cancelDropsTheRunningResult() async {
        let gate = Gate()
        let delivered = Delivered()
        let work = LatestOnly<Int, Int>(work: { n in
            await gate.pass(n)
            return n
        }, deliver: { delivered.values.append($0) })
        work.submit(1)
        work.submit(2)
        await until { await gate.started == [1] }
        work.cancel()
        await gate.open(1)
        await until { !work.isBusy }
        work.submit(4)
        await gate.open(4)
        await until { delivered.values == [4] }
        #expect(await gate.started == [1, 4])
        #expect(delivered.values == [4])
    }
}
