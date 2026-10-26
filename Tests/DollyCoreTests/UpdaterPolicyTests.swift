import Foundation
import Testing
@testable import DollyCore

@Suite struct UpdaterPolicyTests {
    let app = URL(filePath: "/Applications/Dolly.app", directoryHint: .isDirectory)

    @Test func onlyARealBundleGetsAnUpdater() {
        #expect(UpdaterPolicy.allowsUpdater(arguments: ["Dolly"], environment: [:], bundleURL: app))
        #expect(!UpdaterPolicy.allowsUpdater(arguments: ["Dolly", "--shot"], environment: [:], bundleURL: app))
        #expect(!UpdaterPolicy.allowsUpdater(arguments: ["Dolly"], environment: ["DOLLY_NO_UPDATES": "1"], bundleURL: app))
        #expect(!UpdaterPolicy.allowsUpdater(arguments: ["Dolly"], environment: ["XCTestBundlePath": "/x"], bundleURL: app))
        #expect(!UpdaterPolicy.allowsUpdater(arguments: ["Dolly"], environment: [:],
                                             bundleURL: URL(filePath: "/tmp/.build/debug", directoryHint: .isDirectory)))
    }
}
