import CoreGraphics
import Foundation
import Testing
@testable import DollyCore

@Suite struct TakeNameTests {
    func window(_ id: UInt32, _ app: String, _ title: String, _ frame: CGRect) -> PickableWindow {
        PickableWindow(id: id, app: app, title: title, frame: frame, displayID: 1)
    }

    @Test func windowTakeIsNamedLikeTheRecordBar() {
        #expect(TakeName.suggestion(app: "Kalos", title: "Video-only mode | Augment") == "Kalos, Video-only mode | Augment")
        #expect(TakeName.suggestion(app: "Finder", title: "") == "Finder")
        #expect(TakeName.suggestion(app: "Notes", title: "Notes") == "Notes")
    }

    @Test func titleThatEndsWithTheAppDropsIt() {
        #expect(TakeName.suggestion(app: "Safari", title: "Apple - Safari") == "Safari, Apple")
        #expect(TakeName.suggestion(app: "Xcode", title: "Dolly \u{2014} Xcode") == "Xcode, Dolly")
    }

    @Test func longTitlesStopAtAWord() throws {
        let name = try #require(TakeName.suggestion(app: "Kalos", title: String(repeating: "word ", count: 30)))
        #expect(name.count <= TakeName.maxLength)
        #expect(name.hasSuffix("word…"))
    }

    @Test func blankAppAndTitleSuggestNothing() {
        #expect(TakeName.suggestion(app: "  ", title: "\n") == nil)
    }

    @Test func areaAndDisplayTakeTheFrontWindowUnderThem() {
        let windows = [window(1, "Kalos", "apple.com", CGRect(x: 0, y: 0, width: 800, height: 600)),
                       window(2, "Finder", "Downloads", CGRect(x: 1000, y: 0, width: 400, height: 300))]
        let area = CGRect(x: 1100, y: 100, width: 100, height: 100)
        #expect(TakeName.suggestion(target: .area, rect: area, windowID: nil, windows: windows) == "Finder, Downloads")
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        #expect(TakeName.suggestion(target: .display, rect: display, windowID: nil, windows: windows) == "Kalos, apple.com")
        #expect(TakeName.suggestion(target: .window, rect: display, windowID: 2, windows: windows) == "Finder, Downloads")
        #expect(TakeName.suggestion(target: .area, rect: CGRect(x: 3000, y: 3000, width: 10, height: 10), windowID: nil, windows: windows) == nil)
    }

    @Test func repeatedNamesGetANumber() {
        #expect(TakeName.unique("Kalos, apple.com", used: []) == "Kalos, apple.com")
        #expect(TakeName.unique("Kalos, apple.com", used: ["Kalos, apple.com", "Kalos, apple.com 2"]) == "Kalos, apple.com 3")
        #expect(TakeName.unique(nil, used: ["Untitled take 1"]) == "Untitled take 2")
    }
}
