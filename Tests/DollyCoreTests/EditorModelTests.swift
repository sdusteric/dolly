import CoreGraphics
import Testing
@testable import DollyCore

@Suite struct EditorModelTests {
    let model: EditorModel

    init() throws {
        let samples = try Fixtures.shelfDemoSamples()
        let clicks = ClickDetector.clicks(from: samples, geometry: Fixtures.shelfGeometry, recordingStartHost: 0, stopRequestHost: 48.2)
        var take = SyntheticTake.shelfDemo()
        take.zooms = ZoomRules().zooms(for: clicks, size: take.size, target: .window, trim: take.trim)
        let pointer = PointerPath(samples: samples, geometry: Fixtures.shelfGeometry, clicks: clicks, recordingStartHost: 0, look: take.look)
        model = EditorModel(take: take, pointer: pointer)
    }

    var ids: [Zoom.ID] { model.take.zooms.map(\.id) }

    @Test func moveStopsAtNeighbor() {
        model.move(ids[1], by: -10)
        #expect(approx(model.zoom(ids[1])!.start, model.zoom(ids[0])!.end))
        model.move(ids[1], by: 100)
        #expect(approx(model.zoom(ids[1])!.end, model.zoom(ids[2])!.start))
    }

    @Test func resizeKeepsMinimumLength() {
        let z = model.zoom(ids[1])!
        model.resize(ids[1], edge: .end, to: z.start + 0.1)
        #expect(approx(model.zoom(ids[1])!.end, z.start + 1.3))
    }

    @Test func resizeStopsAtNeighbor() {
        model.resize(ids[1], edge: .start, to: 0)
        #expect(approx(model.zoom(ids[1])!.start, model.zoom(ids[0])!.end))
    }

    @Test func trimOverWholeZoomRemovesIt() {
        model.setTrim(5...48.2)
        #expect(model.take.zooms.count == 4)
        model.undo()
        #expect(model.take.zooms.count == 5)
    }

    @Test func trimClampsAPartlyCutZoom() {
        model.setTrim(8.0...48.2)
        #expect(approx(model.take.zooms[0].start, 8.0))
    }

    @Test func addAtPlayheadAimsAtPointer() throws {
        model.addZoom(at: 24.0)
        let added = try #require(model.take.zooms.first { $0.source == .manual })
        #expect(added.depth == 2.0 && approx(added.start, 24.0) && approx(added.length, 2.6))
        #expect(approx(added.aim, try #require(model.pointer?.rawPosition(at: 24.0))))
        #expect(model.selection == added.id)
        #expect(model.take.zooms.map(\.start) == model.take.zooms.map(\.start).sorted())
    }

    @Test func addWhereThereIsNoRoomDoesNothing() {
        model.addZoom(at: 8.0)
        #expect(model.take.zooms.count == 5)
    }

    @Test func depthClamps() {
        model.setDepth(ids[0], 9)
        #expect(model.zoom(ids[0])!.depth == 3.0)
        model.setDepth(ids[0], 0.2)
        #expect(model.zoom(ids[0])!.depth == 1.0)
    }

    @Test func aimStaysInsideTheRecording() {
        model.aim(ids[0], at: CGPoint(x: -50, y: 2000))
        #expect(model.zoom(ids[0])!.aim == CGPoint(x: 0, y: 858))
    }

    @Test func undoRedoEveryEdit() {
        let original = model.take
        model.setDepth(ids[0], 2.5)
        model.move(ids[2], by: 1)
        model.setMode(ids[1], .follow)
        model.setMove(ids[3], moveIn: 1.0, moveOut: nil)
        model.rename(ids[4], "New episode")
        model.remove(ids[0])
        let final = model.take
        for _ in 0..<6 { model.undo() }
        #expect(model.take == original)
        #expect(!model.canUndo)
        for _ in 0..<6 { model.redo() }
        #expect(model.take == final)
    }

    @Test func selectNextWraps() {
        model.select(ids[4])
        model.selectNext()
        #expect(model.selection == ids[0])
    }

    @Test func zoomCountText() {
        model.select(ids[1])
        #expect(model.zoomCountText == "Zoom 2 of 5")
    }

    @Test func moveClampsToMinAndMax() {
        model.setMove(ids[0], moveIn: 5, moveOut: 0)
        #expect(model.zoom(ids[0])!.moveIn == 1.5 && model.zoom(ids[0])!.moveOut == 0.2)
    }
}

@Suite struct EditorGestureTests {
    @Test func aDragIsOneUndoStep() throws {
        var take = SyntheticTake.shelfDemo()
        take.zooms = [Zoom(start: 1, end: 5, aim: CGPoint(x: 100, y: 100), depth: 2, mode: .hold, moveIn: 0.6, moveOut: 0.5,
                           source: .auto, clickIDs: [], name: "")]
        let m = EditorModel(take: take, pointer: nil)
        let id = take.zooms[0].id
        m.beginGesture()
        for x in stride(from: 110.0, through: 200, by: 10) { m.aim(id, at: CGPoint(x: x, y: 100)) }
        m.endGesture()
        #expect(m.zoom(id)?.aim == CGPoint(x: 200, y: 100))
        m.undo()
        #expect(m.zoom(id)?.aim == CGPoint(x: 100, y: 100))
        #expect(!m.canUndo)
    }

    @Test func aGestureThatChangesNothingRecordsNothing() {
        let m = EditorModel(take: SyntheticTake.shelfDemo(), pointer: nil)
        m.beginGesture()
        m.endGesture()
        #expect(!m.canUndo)
    }
}
