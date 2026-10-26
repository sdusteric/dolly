import Foundation

/// When Dolly may start Sparkle (app-updates CONTRACT.md): never in shot mode, never with
/// `DOLLY_NO_UPDATES=1`, never under a test runner, and only from a `.app` bundle, so a bare
/// `.build` binary, tests and dollyctl never reach it.
public enum UpdaterPolicy {
    public static let disableVariable = "DOLLY_NO_UPDATES"

    public static func allowsUpdater(arguments: [String], environment: [String: String], bundleURL: URL) -> Bool {
        if arguments.contains("--shot") { return false }
        if environment[disableVariable] == "1" { return false }
        if environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil { return false }
        return bundleURL.pathExtension == "app"
    }
}
