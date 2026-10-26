import Foundation

/// A global shortcut as Carbon key code and modifiers (spec 3: ⌃⌥⌘R records).
public struct HotkeyCombo: Codable, Hashable, Sendable {
    public enum Modifier {
        public static let command: UInt32 = 256
        public static let shift: UInt32 = 512
        public static let option: UInt32 = 2048
        public static let control: UInt32 = 4096
    }

    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Control-Option-Command-R; kVK_ANSI_R is 15.
    public static let defaultRecord = HotkeyCombo(keyCode: 15, modifiers: Modifier.control | Modifier.option | Modifier.command)

    static let keyNames: [UInt32: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M",
        45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        49: "Space",
    ]

    public var displayString: String {
        var s = ""
        if modifiers & Modifier.control != 0 { s += "⌃" }
        if modifiers & Modifier.option != 0 { s += "⌥" }
        if modifiers & Modifier.shift != 0 { s += "⇧" }
        if modifiers & Modifier.command != 0 { s += "⌘" }
        return s + (Self.keyNames[keyCode] ?? "Key \(keyCode)")
    }
}
