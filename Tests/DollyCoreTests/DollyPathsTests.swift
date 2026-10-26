import Foundation
import Testing
@testable import DollyCore

@Suite struct DollyPathsTests {
    @Test func testHomeRedirectsEverything() {
        let p = DollyPaths(environment: ["DOLLY_HOME": "/tmp/dh"])
        #expect(p.takesFolder.path == "/tmp/dh/Movies/Takes")
        #expect(p.exportsFolder.path == "/tmp/dh/Movies")
        #expect(p.settingsURL.path == "/tmp/dh/Support/settings.json")
        #expect(p.logURL.path == "/tmp/dh/Support/dolly.log")
        #expect(p.isTestHome)
    }

    @Test func defaultsUseMoviesDolly() {
        let p = DollyPaths(environment: ["HOME": "/Users/x"])
        #expect(p.exportsFolder.path == "/Users/x/Movies/Dolly")
        #expect(p.takesFolder.path == "/Users/x/Movies/Dolly/Takes")
        #expect(p.supportFolder.path == "/Users/x/Library/Application Support/Dolly")
        #expect(!p.isTestHome)
    }
}
