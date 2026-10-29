import CoreGraphics
import Foundation
import Testing
@testable import DollyCore

/// dollyctl's commands live in DollyCore (DollyctlCommands) so they are tested without running
/// the binary.
@Suite struct DollyctlTests {
    @Test func dollyctlZoomsOnShelfDemo() throws {
        let lines = DollyctlCommands.zoomLines(samples: try Fixtures.shelfDemoSamples(),
                                               size: CGSize(width: 848, height: 858), target: .window)
        #expect(lines.count == 5)
        #expect(lines[0].hasPrefix("1.8 4.4 1.6x hold"))
        #expect(lines[1].hasPrefix("7.3 9.9 1.6x hold (636, 318) Click at 0:07.9"))
    }

    @Test func parsesSizeAndTarget() {
        #expect(DollyctlCommands.parseSize("848x858") == CGSize(width: 848, height: 858))
        #expect(DollyctlCommands.parseSize("848") == nil)
        #expect(DollyctlCommands.parseTimes("0,8.6") == [0, 8.6])
    }

    @Test func cameraLineAtRestAndInsideAZoom() throws {
        var take = SyntheticTake.shelfDemo()
        let clicks = ClickDetector.clicks(from: try Fixtures.shelfDemoSamples(), geometry: Fixtures.shelfGeometry,
                                          recordingStartHost: 0, stopRequestHost: 48.2)
        take.zooms = ZoomRules().zooms(for: clicks, size: take.size, target: .window, trim: 0...48.2)
        #expect(DollyctlCommands.cameraLine(take: take, pointer: nil, at: 0).hasPrefix("0.0 1.00x"))
        #expect(DollyctlCommands.cameraLine(take: take, pointer: nil, at: 8.6).hasPrefix("8.6 1.60x"))
    }

    /// `dollyctl fixture shelf-demo` regenerates the committed fixture (Task 3) from code, to the
    /// hundredth of a point (the fixture rounded halves to even).
    @Test func shelfDemoGeneratorMatchesFixture() throws {
        let fixture = try Fixtures.shelfDemoSamples()
        let made = SyntheticTake.shelfDemoSamples()
        #expect(made.count == fixture.count)
        for (a, b) in zip(made, fixture) {
            #expect(approx(a.t, b.t, tol: 1e-5) && abs(a.x - b.x) < 0.011 && abs(a.y - b.y) < 0.011 && a.buttons == b.buttons,
                    "\(a) vs \(b)")
            if !(approx(a.t, b.t, tol: 1e-5) && abs(a.x - b.x) < 0.011 && abs(a.y - b.y) < 0.011 && a.buttons == b.buttons) { break }
        }
    }

    @Test func renderAcceptsEveryShape() throws {
        #expect(try DollyctlCommands.parseShape("4x5") == .portrait4x5)
        #expect(try DollyctlCommands.parseShape("original") == .original)
        #expect(try DollyctlCommands.parseShape("16x9") == .wide16x9)
        #expect(throws: DollyctlCommands.UsageError.self) { try DollyctlCommands.parseShape("3x2") }
    }

    @Test func captionsCommandPrintsSRT() {
        var take = SyntheticTake.shelfDemo()
        take.trim = 1.0...40
        take.captions = CaptionTrack(source: .typed, locale: "en_US", items: [
            Caption(start: 1.4, end: 3.8, text: "This is Shelf."),
            Caption(start: 4.2, end: 7.25, text: "Haul shows downloads."),
        ])
        #expect(DollyctlCommands.captionsSRT(take) == """
        1
        00:00:00,400 --> 00:00:02,800
        This is Shelf.

        2
        00:00:03,200 --> 00:00:06,250
        Haul shows downloads.

        """)
        #expect(DollyctlCommands.captionsSRT(SyntheticTake.shelfDemo()).isEmpty)
    }
}
