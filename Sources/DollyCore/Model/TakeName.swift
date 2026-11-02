import CoreGraphics
import Foundation

/// A new take's name, from what was recorded: the window's app and title, as the Record bar
/// labels it. An area or display takes the front window under it. Nothing found: "Untitled take N".
public enum TakeName {
    public static let maxLength = 60

    public static func suggestion(target: TargetKind, rect: CGRect, windowID: UInt32?, windows: [PickableWindow]) -> String? {
        let window: PickableWindow? = switch target {
        case .window: windows.first { $0.id == windowID }
        case .area, .display:
            // `windows` is front to back, so the first one under the recording is the one in view.
            windows.first { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) || rect.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
        }
        return window.flatMap { suggestion(app: $0.app, title: $0.title) }
    }

    public static func suggestion(app: String, title: String) -> String? {
        let app = tidy(app)
        var title = tidy(title)
        // "Apple - Safari" already says Safari in front.
        for separator in [" - ", " \u{2014} ", " \u{2013} ", " | "] where !app.isEmpty && title.hasSuffix(separator + app) {
            title = String(title.dropLast(separator.count + app.count))
        }
        let name = title.isEmpty || title == app ? app : app.isEmpty ? title : "\(app), \(title)"
        return name.isEmpty ? nil : shortened(name)
    }

    /// `base`, or `base 2`, `base 3` when that name is taken.
    public static func unique(_ base: String?, used: Set<String>) -> String {
        guard let base else {
            var n = 1
            while used.contains("Untitled take \(n)") { n += 1 }
            return "Untitled take \(n)"
        }
        guard used.contains(base) else { return base }
        var n = 2
        while used.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    private static func tidy(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func shortened(_ name: String) -> String {
        guard name.count > maxLength else { return name }
        let cut = name.prefix(maxLength - 1)
        let word = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return word.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) + "…"
    }
}
