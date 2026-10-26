import Foundation

/// Where Dolly keeps takes, exports, settings and its log (spec section 8). `DOLLY_HOME` moves all
/// of it into one folder, which every test, shot and dollyctl run sets to a fresh temp dir.
public struct DollyPaths: Sendable, Hashable {
    /// Exports land here; takes live in `Takes/` inside it.
    public let exportsFolder: URL
    public let takesFolder: URL
    public let supportFolder: URL
    /// Shelf's own status folder by default; inside `DOLLY_HOME` otherwise, so no test, shot or
    /// tool writes into the real one.
    public let shelfStatusFolder: URL
    public let isTestHome: Bool

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let home = environment["DOLLY_HOME"], !home.isEmpty {
            let root = URL(filePath: home, directoryHint: .isDirectory)
            exportsFolder = root.appending(path: "Movies", directoryHint: .isDirectory)
            supportFolder = root.appending(path: "Support", directoryHint: .isDirectory)
            shelfStatusFolder = root.appending(path: "ShelfStatus", directoryHint: .isDirectory)
            isTestHome = true
        } else {
            let user = URL(filePath: environment["HOME"] ?? NSHomeDirectory(), directoryHint: .isDirectory)
            exportsFolder = user.appending(path: "Movies/Dolly", directoryHint: .isDirectory)
            supportFolder = user.appending(path: "Library/Application Support/Dolly", directoryHint: .isDirectory)
            shelfStatusFolder = user.appending(path: "Library/Application Support/Shelf/status", directoryHint: .isDirectory)
            isTestHome = false
        }
        takesFolder = exportsFolder.appending(path: "Takes", directoryHint: .isDirectory)
    }

    public var settingsURL: URL { supportFolder.appending(path: "settings.json", directoryHint: .notDirectory) }
    public var logURL: URL { supportFolder.appending(path: "dolly.log", directoryHint: .notDirectory) }
}
