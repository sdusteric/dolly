import AppKit

/// A borderless panel that can take key focus without activating Dolly, so Esc and Return reach
/// the Record bar and the area picker. Plain borderless panels refuse key focus.
public final class KeyablePanel: NSPanel {
    override public var canBecomeKey: Bool { true }
}
