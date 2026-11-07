import Foundation
import Testing
@testable import DollyCore

/// Cuts and speed-ups in the editor: each edit one undo step, regions inside the trim, never
/// overlapping, and never cutting the whole clip away.
@MainActor @Suite struct SpeedEditTests {
    func editor(duration: Double = 10) -> EditorModel {
        EditorModel(take: Take(name: "t", target: .display, size: CGSize(width: 100, height: 100), pixelScale: 1, fps: 60,
                               duration: duration), pointer: nil)
    }

    @Test func cutAtThePlayheadIsTwoSecondsAndSelected() throws {
        let e = editor()
        e.addCut(at: 3)
        let region = try #require(e.take.speedRegions.first)
        #expect(region.start == 3 && region.end == 5 && region.speed == .cut)
        #expect(e.selection == .speed(region.id))
        #expect(e.take.outputDuration == 8)
        e.undo()
        #expect(e.take.speedRegions.isEmpty && e.selection == nil)
    }

    @Test func cutNearTheEndStopsAtTheTrim() throws {
        let e = editor()
        e.addCut(at: 9)
        #expect(e.take.speedRegions.first?.end == 10)
    }

    @Test func addingIntoAnotherRegionDoesNothing() {
        let e = editor()
        e.addSpeed(from: 2, to: 6, speed: .fast(4))
        e.addCut(at: 4)
        #expect(e.take.speedRegions.count == 1)
        // A drag that runs into it stops at its edge.
        e.addSpeed(from: 7, to: 5, speed: .cut)
        #expect(e.take.speedRegions.map(\.start) == [2, 6] && e.take.speedRegions.last?.end == 7)
    }

    @Test func neverCutsTheWholeClip() {
        let e = editor(duration: 3)
        e.addSpeed(from: 0, to: 3, speed: .cut)
        #expect(e.take.speedRegions.isEmpty)
        e.addSpeed(from: 0, to: 2.8, speed: .cut)
        #expect(e.take.speedRegions.isEmpty)
        e.addSpeed(from: 0, to: 2, speed: .cut)
        #expect(e.take.speedRegions.count == 1)
    }

    @Test func changeSpeedResizeMoveAndRemove() throws {
        let e = editor()
        e.addSpeed(from: 2, to: 4, speed: .cut)
        e.addSpeed(from: 6, to: 8, speed: .cut)
        let id = try #require(e.take.speedRegions.first?.id)
        e.setSpeed(id, .fast(8))
        #expect(e.take.speedRegions.first?.speed == .fast(8))
        e.resizeSpeed(id, edge: .end, to: 7)
        #expect(e.take.speedRegions.first?.end == 6)
        e.resizeSpeed(id, edge: .start, to: 5.95)
        #expect(approx(e.take.speedRegions.first?.length ?? 0, EditorModel.speedMinimum))
        e.moveSpeed(id, by: -10)
        #expect(e.take.speedRegions.first?.start == 0)
        e.removeSpeed(id)
        #expect(e.take.speedRegions.count == 1)
        for _ in 0..<5 { e.undo() }
        #expect(e.take.speedRegions.first?.speed == .cut && e.take.speedRegions.first?.end == 4)
    }

    @Test func deleteKeyRemovesTheSelectedRegion() throws {
        let e = editor()
        e.addCut(at: 1)
        #expect(e.selection != nil)
        e.removeSelected()
        #expect(e.take.speedRegions.isEmpty && e.selection == nil)
    }
}
