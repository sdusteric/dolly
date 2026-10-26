import Foundation

/// The actions Shelf can open through `dolly://<action>` (app-updates CONTRACT.md, Shelf section).
/// Anything outside the allowlist is nil.
public enum DollyURL: String, Sendable, CaseIterable {
    case record
    case openLatest = "open-latest"
    case checkForUpdates = "check-for-updates"

    public static let scheme = "dolly"

    /// The value of `SDShelfActions` in Info.plist.
    public static var advertisedActions: [String] { allCases.map(\.rawValue) }

    /// Accepts only `dolly://<action>` with no path, query, fragment, user or port.
    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.query == nil, parts.fragment == nil, parts.user == nil, parts.password == nil, parts.port == nil,
              parts.path.isEmpty || parts.path == "/",
              let host = parts.host?.lowercased()
        else { return nil }
        self.init(rawValue: host)
    }
}
