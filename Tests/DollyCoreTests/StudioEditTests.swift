import CoreGraphics
import Foundation
import Testing
@testable import DollyCore

@Suite struct StudioEditTests {
    let model: EditorModel

    init() {
        var take = SyntheticTake.shelfDemo()
        take.zooms = [Zoom(start: 2, end: 5, aim: CGPoint(x: 300, y: 300), depth: 2, mode: .hold, moveIn: 0.6, moveOut: 0.5,
                           source: .auto, clickIDs: [], name: "a")]
        take.camera = CameraTrack(startOffset: 0)
        take.captions = SyntheticTake.shelfCaptions()
        model = EditorModel(take: take, pointer: nil)
    }

    var items: [Caption] { model.take.captions?.items ?? [] }
    func id(_ i: Int) -> Caption.ID { items[i].id }

    @Test func splitCaptionByCharacters() throws {
        let fourth = id(3)
        model.splitCaption(fourth, at: 14)
        let a = items[3], b = items[4]
        #expect(a.text == "Each tile has" && b.text == "its own quick actions.")
        #expect(approx(a.start, 11.4) && approx(b.end, 14.6))
        #expect(approx(a.end, 11.4 + 3.2 * 14 / 36) && a.end == b.start)
        #expect(model.take.captions?.edited == true)
        #expect(model.selection == .caption(b.id))
        model.undo()
        #expect(items.count == 10 && items[3].text == "Each tile has its own quick actions.")
    }

    @Test func joinKeepsTimes() {
        let second = id(1)
        model.joinCaption(second)
        #expect(items.count == 9)
        #expect(items[0].text == "This is Shelf, my launcher for every app. Haul shows what is downloading.")
        #expect(approx(items[0].start, 0.4) && approx(items[0].end, 7.2))
        model.joinCaption(id(0))   // the first has none before it
        #expect(items.count == 9)
    }

    @Test func captionsNeverOverlap() {
        model.moveCaption(id(3), by: -5)
        #expect(approx(items[3].start, items[2].end))
        model.moveCaption(id(3), by: 50)
        #expect(approx(items[3].end, items[4].start))
        model.resizeCaption(id(5), edge: .start, to: 0)
        #expect(approx(items[5].start, items[4].end))
        model.resizeCaption(id(5), edge: .end, to: items[5].start + 0.1)
        #expect(approx(items[5].end - items[5].start, 0.4))
    }

    @Test func editAndAddCaptions() {
        model.editCaption(id(0), text: "Hello.")
        #expect(items[0].text == "Hello.")
        model.addCaption(at: 11.1)   // the gap between captions 3 and 4 is only 0.4 s
        #expect(items.count == 10)
        model.addCaption(at: 48.0)
        #expect(items.count == 10)   // 47.8 to the end is too short too
        let typed = EditorModel(take: SyntheticTake.shelfDemo(), pointer: nil)
        typed.addCaption(at: 3)
        let added = typed.take.captions?.items ?? []
        #expect(typed.take.captions?.source == .typed && added.count == 1)
        #expect(added[0].start == 3 && added[0].end == 5 && added[0].text.isEmpty)
        #expect(typed.selection == .caption(added[0].id))
    }

    @Test func setCaptionsClearsEdited() {
        model.editCaption(id(0), text: "x")
        model.setCaptions(SyntheticTake.shelfCaptions())
        #expect(model.take.captions?.edited == false && items[0].text == "This is Shelf, my launcher for every app.")
    }

    @Test func hiddenCameraRangesMerge() {
        model.hideCamera(from: 3, to: 5)
        model.hideCamera(from: 8, to: 4)
        #expect(model.take.camera?.hidden == [3...8])
        model.hideCamera(from: 20, to: 22)
        model.resizeCameraGap(index: 1, edge: .start, to: 1)
        #expect(model.take.camera?.hidden == [3...8, 8...22])
        model.showCamera(range: 0)
        #expect(model.take.camera?.hidden == [8...22])
        model.undo()
        #expect(model.take.camera?.hidden == [3...8, 8...22])
    }

    @Test func setCameraIsOneUndoStep() {
        model.setCamera { $0.size = 0.9 }
        #expect(model.take.camera?.size == CameraTrack.sizeRange.upperBound)
        model.setCamera { $0.corner = .topRight }
        model.undo()
        #expect(model.take.camera?.corner == .bottomLeft)
    }

    @Test func shapeChangeKeepsZooms() {
        let before = model.take.zooms
        model.setShape(.tall9x16)
        #expect(model.take.currentShape == .tall9x16 && model.take.zooms == before)
        model.setBackdrop(.gradient(id: "moss"))
        #expect(model.take.look.background == .gradient(id: "moss"))
        model.undo()
        model.undo()
        #expect(model.take.currentShape == .wide16x9)
    }

    @Test func selectionKinds() {
        let zoom = model.take.zooms[0].id
        model.select(zoom)
        #expect(model.selectedZoom == zoom && model.selection == .zoom(zoom))
        model.selectCamera()
        #expect(model.selectedZoom == nil && model.selection == .camera)
        model.selectCaption(id(2))
        #expect(model.selection == .caption(id(2)))
        model.select(nil)
        #expect(model.selection == nil)
    }
}
