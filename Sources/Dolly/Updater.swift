import DollyCore
import Foundation
import Sparkle

/// Sparkle 2 (app-updates CONTRACT.md). The feed, key and schedule come from Info.plist. Only
/// `AppDelegate` creates it, through `make()`, which follows `UpdaterPolicy`.
@MainActor
final class Updater {
    private let controller: SPUStandardUpdaterController

    static func make(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleURL: URL = Bundle.main.bundleURL
    ) -> Updater? {
        UpdaterPolicy.allowsUpdater(arguments: arguments, environment: environment, bundleURL: bundleURL) ? Updater() : nil
    }

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
