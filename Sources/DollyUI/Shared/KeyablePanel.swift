import AppKit

/// A borderless panel that can take key focus without activating Dolly, so Esc and Return reach
/// the Record bar and the area picker. Plain borderless panels refuse key focus.
public final class KeyablePanel: NSPanel {
    override public var canBecomeKey: Bool { true }
}

/// A sheet that hears Esc. AppKit sends Esc to the window as cancelOperation, and a SwiftUI
/// `.cancelAction` button inside an NSHostingView with nothing focused never sees it.
public final class SheetWindow: NSWindow {
    public var onCancel: () -> Void = {}
    override public func cancelOperation(_ sender: Any?) { onCancel() }
}
