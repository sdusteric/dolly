import Foundation

public final class SettingsStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public convenience init(paths: DollyPaths) { self.init(url: paths.settingsURL) }

    /// Defaults when there is no file yet; a damaged file throws so the caller can log it.
    public func load() throws -> Settings {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return Settings() }
        return try JSONDecoder().decode(Settings.self, from: Data(contentsOf: url))
    }

    public func save(_ settings: Settings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try AtomicFile.write(try encoder.encode(settings), to: url)
    }
}
