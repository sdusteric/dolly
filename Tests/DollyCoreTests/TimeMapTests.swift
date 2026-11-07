import Foundation
import Testing
@testable import DollyCore

/// Source time (the take) to output time (the export) through the trim, cuts and speed-ups.
@Suite struct TimeMapTests {
    func region(_ start: Double, _ end: Double, _ speed: SpeedRegion.Speed) -> SpeedRegion {
        SpeedRegion(start: start, end: end, speed: speed)
    }

    @Test func noRegionsIsTheTrim() {
        let map = TimeMap(trim: 2...10, regions: [])
        #expect(map.duration == 8)
        #expect(map.output(at: 2) == 0 && map.output(at: 6) == 4 && map.output(at: 10) == 8)
        #expect(map.source(at: 0) == 2 && map.source(at: 4) == 6 && map.source(at: 8) == 10)
        // Outside the trim clamps to its ends.
        #expect(map.output(at: 0) == 0 && map.output(at: 12) == 8)
    }

    @Test func aCutRemovesItsStretch() {
        let map = TimeMap(trim: 0...10, regions: [region(3, 5, .cut)])
        #expect(map.duration == 8)
        #expect(map.output(at: 3) == 3 && map.output(at: 5) == 3 && map.output(at: 7) == 5)
        // Any time inside the cut lands where the cut was.
        #expect(map.output(at: 4) == 3)
        #expect(map.source(at: 2) == 2 && map.source(at: 3) == 5 && map.source(at: 6) == 8)
        #expect(map.isCut(4) && !map.isCut(6))
    }

    @Test func aSpeedUpShortensItsStretch() {
        let map = TimeMap(trim: 0...10, regions: [region(2, 6, .fast(4))])
        #expect(map.duration == 7)
        #expect(map.output(at: 4) == 2.5 && map.output(at: 6) == 3)
        #expect(map.source(at: 2.5) == 4 && map.source(at: 5) == 8)
        #expect(map.pieces.map(\.rate) == [1, 4, 1])
    }

    @Test func regionsAreClippedToTheTrimAndSorted() {
        let map = TimeMap(trim: 1...9, regions: [region(8, 12, .cut), region(0, 2, .fast(2))])
        #expect(map.pieces.map(\.start) == [1, 2])
        #expect(map.pieces.map(\.end) == [2, 8])
        #expect(map.duration == 0.5 + 6)
    }

    @Test func overlapsKeepTheFirstRegion() {
        let map = TimeMap(trim: 0...10, regions: [region(2, 5, .cut), region(4, 7, .fast(2))])
        #expect(map.pieces.map(\.start) == [0, 5, 7])
        #expect(map.pieces.map(\.rate) == [1, 2, 1])
    }

    @Test func cuttingEverythingKeepsTheTrim() {
        let map = TimeMap(trim: 0...4, regions: [region(0, 4, .cut)])
        #expect(map.duration == 4)
    }

    @Test func takeOutputLengthUsesTheMap() {
        var take = Take(name: "t", target: .display, size: CGSize(width: 100, height: 100), pixelScale: 1, fps: 60, duration: 10)
        #expect(take.outputDuration == 10)
        take.speedRegions = [region(0, 4, .cut)]
        #expect(take.outputDuration == 6)
        #expect(take.compositionInputs != Take(name: "t", target: .display, size: take.size, pixelScale: 1, fps: 60, duration: 10).compositionInputs)
    }

    @Test func oldTakesDecodeWithNoRegions() throws {
        let take = Take(name: "t", target: .display, size: CGSize(width: 100, height: 100), pixelScale: 1, fps: 60, duration: 10)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(take)) as? [String: Any] ?? [:]
        json["speeds"] = nil
        let decoded = try JSONDecoder().decode(Take.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.speedRegions.isEmpty)
    }

    @Test func srtTimesFollowCutsAndDropCutCaptions() {
        let map = TimeMap(trim: 1...11, regions: [region(3, 5, .cut)])
        let items = [Caption(start: 1.5, end: 2.5, text: "one"), Caption(start: 3.2, end: 4.8, text: "gone"),
                     Caption(start: 6, end: 7, text: "two")]
        #expect(SRT.text(items, map: map) == """
        1
        00:00:00,500 --> 00:00:01,500
        one

        2
        00:00:03,000 --> 00:00:04,000
        two

        """)
    }
}
