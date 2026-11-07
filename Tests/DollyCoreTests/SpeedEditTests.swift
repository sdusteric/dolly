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

    /// Review: resizing a cut or moving the trim never cuts the whole clip away.
    @Test func resizeAndTrimNeverCutEverything() throws {
        let e = editor()
        e.addSpeed(from: 2, to: 4, speed: .cut)
        let id = try #require(e.take.speedRegions.first?.id)
        e.resizeSpeed(id, edge: .start, to: 0)
        e.resizeSpeed(id, edge: .end, to: 10)
        #expect(e.take.outputDuration >= EditorModel.clipMinimum)
        e.resizeSpeed(id, edge: .end, to: 9.8)
        #expect(e.take.outputDuration >= EditorModel.clipMinimum)
        let before = e.take.trim
        e.setTrim(2...4)
        #expect(e.take.outputDuration >= EditorModel.clipMinimum)
        #expect(e.take.trim == before || e.take.outputDuration >= EditorModel.clipMinimum)
    }
}

@Suite struct TimeMapGridTests {
    /// Review: piece edges sit on the composition's 1/600 s grid, so clip times built from them
    /// and from CMTime never drift apart, however many pieces there are.
    @Test func piecesSitOnTheCompositionGrid() {
        var regions: [SpeedRegion] = []
        for i in 0..<12 { regions.append(SpeedRegion(start: Double(i) * 0.8 + 0.1234567, end: Double(i) * 0.8 + 0.4567891, speed: i % 2 == 0 ? .cut : .fast(3))) }
        let map = TimeMap(trim: 0.0101...10.0303, regions: regions)
        for piece in map.pieces {
            for t in [piece.start, piece.end, piece.outputStart, piece.outputEnd] {
                #expect(abs(t * 600 - (t * 600).rounded()) < 1e-6)
            }
        }
    }
}

