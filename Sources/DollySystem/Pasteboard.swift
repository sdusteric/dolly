import AppKit
import Foundation

/// Copy after export (spec 7): file URLs, so a browser upload field accepts a paste.
/// Never called from tests; they pass a named pasteboard.
public enum Pasteboard {
    @MainActor
    public static func copyFiles(_ urls: [URL], to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }
}
