import Foundation
import Testing
@testable import DollyCore

/// A take.json as M1 wrote it: no shape, camera or captions, and `shadow` as a Bool.
func m1TakeJSON(shadow: String = "true") -> String {
    ##"{"version":1,"id":"6B1F2C1E-8C2B-4D0B-9A40-1D2C3B4A5F60","name":"Old","created":0,"target":"window","size":[848,858],"pixelScale":2,"fps":60,"duration":10,"trim":[0,10],"look":{"background":{"color":{"hex":"#3E4A4F"}},"padding":64,"corners":12,"shadow":"##
        + shadow + ##","pointerScale":1.5,"smoothPointer":true,"clickRing":true,"hideWhenStill":false},"zooms":[],"exports":[],"recordingStartHost":0,"notes":[]}"##
}

@Suite struct LookTests {
    @Test func m1TakeDecodes() throws {
        let take = try JSONDecoder().decode(Take.self, from: Data(m1TakeJSON().utf8))
        #expect(take.look.shadow == 0.6)
        #expect(take.currentShape == .wide16x9)
    }

    @Test func shadowFalseReadsAsZero() throws {
        let take = try JSONDecoder().decode(Take.self, from: Data(m1TakeJSON(shadow: "false").utf8))
        #expect(take.look.shadow == 0)
    }

    @Test func newLookRoundTrips() throws {
        var look = Look()
        look.background = .picture(file: "backdrop.jpg", blur: 12)
        look.shadow = 0.35
        let back = try JSONDecoder().decode(Look.self, from: JSONEncoder().encode(look))
        #expect(back == look)
    }

    @Test func sixFlatColorsEndInNearBlack() {
        #expect(Look.flatColors == ["#3E4A4F", "#D9CFC0", "#1F2A44", "#F2F2F2", "#7A3B2E", "#151413"])
    }

    @Test func sixGradientsInMockupOrder() {
        #expect(Backdrop.gradients.map(\.id) == ["harbor", "ember", "slate", "moss", "rose", "sand"])
        #expect(Backdrop.gradient("rose")?.top == "#D2577F")
        #expect(Backdrop.gradient("nope") == nil)
    }

    @Test func missingPictureFallsBackToDefault() throws {
        let folder = tempURL("look")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var look = Look()
        look.background = .picture(file: "backdrop.jpg", blur: 0)
        #expect(look.resolved(in: folder).background == .color(hex: Look.flatColors[0]))
        try Data([1]).write(to: folder.appending(path: "backdrop.jpg"))
        #expect(look.resolved(in: folder).background == look.background)
        look.background = .gradient(id: "gone")
        #expect(look.resolved(in: folder).background == .color(hex: Look.flatColors[0]))
    }
}
