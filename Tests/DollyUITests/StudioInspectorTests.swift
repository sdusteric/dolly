import CoreGraphics
import Foundation
import Testing
@testable import DollyCore
@testable import DollyUI

@Suite struct StudioInspectorTests {
    @Test func tabsInOrder() {
        #expect(StudioTab.allCases.map(\.label) == ["Look", "Zooms", "Camera", "Captions"])
    }

    @Test func selectingSwitchesTabAndEscReturns() {
        let id = UUID()
        #expect(StudioInspectorModel.tab(for: .zoom(id), previous: .look) == .zooms)
        #expect(StudioInspectorModel.tab(for: .caption(id), previous: .look) == .captions)
        #expect(StudioInspectorModel.tab(for: .camera, previous: .look) == .camera)
        #expect(StudioInspectorModel.tab(for: nil, previous: .look) == .look)
        #expect(StudioInspectorModel.tab(for: nil, previous: .camera) == .camera)
    }

    @Test func shapeNoteNamesTheSize() {
        let shelf = CGSize(width: 848, height: 858)
        #expect(StudioInspectorModel.shapeNote(.portrait4x5, recording: shelf) == "Exports 1080 × 1350 for X and Threads")
        #expect(StudioInspectorModel.shapeNote(.original, recording: shelf) == "Exports 1898 × 1920 for X and Threads")
    }

    @Test func blurRowOnlyForPictures() {
        #expect(StudioInspectorModel.showsBlur(.picture(file: "backdrop.jpg", blur: 0)))
        #expect(!StudioInspectorModel.showsBlur(.gradient(id: "rose")))
        #expect(!StudioInspectorModel.showsBlur(.color(hex: "#151413")))
    }

    @Test func valueTexts() {
        #expect(StudioInspectorModel.percentText(0.6) == "60%")
        #expect(StudioInspectorModel.percentText(0.224) == "22%")
        #expect(StudioInspectorModel.captionHeader(index: 3, count: 10) == "Caption 4 of 10")
        #expect(StudioInspectorModel.captionTimes(Caption(start: 11.4, end: 14.6, text: "")) == "0:11.4 to 0:14.6")
        #expect(StudioInspectorModel.languageLine("en_US") == "English, transcribed on this Mac.")
    }

    @Test func noZoomSelectedHint() {
        #expect(StudioInspectorModel.zoomsHint(count: 5) == "5 zooms. Select a zoom on the timeline or press Z to add one at the playhead.")
        #expect(StudioInspectorModel.zoomsHint(count: 1).hasPrefix("1 zoom."))
        #expect(StudioInspectorModel.zoomsHint(count: 0).hasPrefix("No zooms."))
    }

    @Test func cameraHiddenByTheSwitch() {
        var camera = CameraTrack(startOffset: 0)
        camera.shown = false
        #expect(!camera.isVisible(at: 1))
    }
}
