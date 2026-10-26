import Foundation
import Testing
@testable import DollyCore

@Suite struct DollyURLTests {
    @Test func urlAllowlist() throws {
        #expect(DollyURL(try #require(URL(string: "dolly://record"))) == .record)
        #expect(DollyURL(try #require(URL(string: "dolly://open-latest"))) == .openLatest)
        #expect(DollyURL(try #require(URL(string: "DOLLY://check-for-updates/"))) == .checkForUpdates)
        #expect(DollyURL(try #require(URL(string: "dolly://delete"))) == nil)
    }

    @Test func rejectsAnythingButABareAction() throws {
        for text in ["dolly://record?take=1", "dolly://record#x", "dolly://record/extra", "dolly://me@record",
                     "dolly://record:80", "snap://record", "dolly:record"] {
            #expect(DollyURL(try #require(URL(string: text))) == nil, "\(text)")
        }
    }

    @Test func advertisedActionsMatchInfoPlist() {
        #expect(DollyURL.advertisedActions == ["record", "open-latest", "check-for-updates"])
    }
}
