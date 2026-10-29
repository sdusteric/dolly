import CoreGraphics
import Foundation
import Testing
@testable import DollyCore
@testable import DollyUI

@Suite struct TimelineLayoutTests {
    let zoom = Zoom(start: 7.3, end: 9.9, aim: .zero, depth: 1.6, mode: .hold, moveIn: 0.6, moveOut: 0.5, source: .auto,
                    clickIDs: [1], name: "Run check up")
    var layout: TimelineLayout { TimelineLayout(width: 1100, duration: 48.2) }

    @Test func xAndTRoundTrip() {
        #expect(abs(layout.x(for: 24.1) - 550) < 0.001)
        #expect(abs(layout.t(for: layout.x(for: 13.37)) - 13.37) < 0.0001)
        #expect(layout.t(for: -50) == 0 && layout.t(for: 5000) == 48.2)
    }

    @Test func rulerTicksEveryFiveSecondsUnderAMinute() {
        let ticks = layout.rulerTicks
        #expect(ticks.first?.label == "0:00" && ticks[1].label == "0:05" && ticks.last?.label == "0:45")
        #expect(TimelineLayout(width: 1100, duration: 150).rulerTicks[1].label == "0:10")
        #expect(TimelineLayout(width: 1100, duration: 400).rulerTicks[1].label == "0:30")
    }

    @Test func stripBandsAreTheMoves() {
        let s = layout.strip(for: zoom)
        #expect(abs(s.frame.minX - layout.x(for: 7.3)) < 0.001 && abs(s.frame.width - layout.x(for: 2.6)) < 0.001)
        #expect(abs(s.inBand.width - layout.x(for: 0.6)) < 0.001 && abs(s.outBand.maxX - s.frame.maxX) < 0.001)
    }

    @Test func hitsStripEdgesWithin6pt() {
        let s = layout.strip(for: zoom).frame
        let y = TimelineLayout.zoomLane.midY
        #expect(layout.hit(CGPoint(x: s.minX + 4, y: y), zooms: [zoom]) == .strip(zoom.id, .startEdge))
        #expect(layout.hit(CGPoint(x: s.maxX - 5, y: y), zooms: [zoom]) == .strip(zoom.id, .endEdge))
        #expect(layout.hit(CGPoint(x: s.midX, y: y), zooms: [zoom]) == .strip(zoom.id, .body))
    }

    @Test func emptyLaneHitGivesTime() {
        let hit = layout.hit(CGPoint(x: layout.x(for: 30), y: TimelineLayout.zoomLane.midY), zooms: [zoom])
        guard case .emptyZoomLane(let t) = hit else { Issue.record("got \(hit)"); return }
        #expect(abs(t - 30) < 0.001)
    }

    @Test func rulerAndTrimHits() {
        guard case .ruler(let t) = layout.hit(CGPoint(x: layout.x(for: 12), y: TimelineLayout.ruler.midY), zooms: []) else {
            Issue.record("no ruler hit"); return
        }
        #expect(abs(t - 12) < 0.001)
        let trim = layout.hit(CGPoint(x: layout.x(for: 48.2) - 3, y: TimelineLayout.videoLane.midY), zooms: [], trim: 0...48.2)
        #expect(trim == .trim(.end))
    }

    @Test func voiceOverLabel() {
        #expect(TimelineAccessibility.label(zoom, index: 1, count: 5) == "Zoom 2 of 5, 0:07.3 to 0:09.9, 1.6 times, holds on Run check up")
        var follow = zoom
        follow.mode = .follow
        #expect(TimelineAccessibility.label(follow, index: 0, count: 1).hasSuffix("follows the pointer, Run check up"))
    }

    @Test func hintCountsClicksAndZooms() {
        #expect(TimelineHint.text(clicks: 9, zooms: 5) == "9 clicks became 5 zooms. Clicks less than 3 s apart share one zoom. Press Z to add a zoom at the playhead.")
        #expect(TimelineHint.text(clicks: 0, zooms: 0) == "No clicks in this take. Press Z to add a zoom at the playhead.")
        #expect(TimelineHint.text(clicks: 1, zooms: 1).hasPrefix("1 click became 1 zoom."))
    }
}

@MainActor @Suite struct TimelineInputTests {
    func model() -> EditorModel {
        var take = SyntheticTake.shelfDemo()
        take.zooms = [Zoom(start: 1, end: 4, aim: .zero, depth: 2, mode: .hold, moveIn: 0.6, moveOut: 0.5, source: .auto, clickIDs: [], name: ""),
                      Zoom(start: 10, end: 13, aim: .zero, depth: 2, mode: .hold, moveIn: 0.6, moveOut: 0.5, source: .auto, clickIDs: [], name: "")]
        let m = EditorModel(take: take, pointer: nil)
        m.playhead = 20
        return m
    }

    @Test func keysMapToActions() {
        #expect(TimelineInput.action(key: "z", shift: false, command: false) == .addZoom)
        #expect(TimelineInput.action(key: .delete, shift: false, command: false) == .removeSelected)
        #expect(TimelineInput.action(key: .tab, shift: false, command: false) == .selectNext)
        #expect(TimelineInput.action(key: " ", shift: false, command: false) == .togglePlay)
        #expect(TimelineInput.action(key: .leftArrow, shift: true, command: false) == .step(seconds: -1))
        #expect(TimelineInput.action(key: "z", shift: false, command: true) == .undo)
        #expect(TimelineInput.action(key: "z", shift: true, command: true) == .redo)
        #expect(TimelineInput.action(key: "l", shift: false, command: false) == .shuttle(1))
    }

    @Test func keysCallModel() {
        let m = model()
        TimelineInput.apply(.addZoom, to: m, playback: nil)
        #expect(m.take.zooms.count == 3)
        TimelineInput.apply(.removeSelected, to: m, playback: nil)
        #expect(m.take.zooms.count == 2)
        TimelineInput.apply(.selectNext, to: m, playback: nil)
        #expect(m.selectedZoom == m.take.zooms[0].id)
        TimelineInput.apply(.step(seconds: -1), to: m, playback: nil)
        #expect(abs(m.playhead - 19) < 0.001)
        TimelineInput.apply(.undo, to: m, playback: nil)
        #expect(m.take.zooms.count == 3)
    }

    @Test func frameStepUsesTheTakeRate() {
        #expect(TimelineInput.action(key: .rightArrow, shift: false, command: false) == .step(seconds: nil))
        #expect(TimelineInput.action(key: .leftArrow, shift: false, command: false) == .stepBack)
        let m = model()
        TimelineInput.apply(.step(seconds: nil), to: m, playback: nil)
        #expect(abs(m.playhead - (20 + 1.0 / 60)) < 0.0001)
    }
}
