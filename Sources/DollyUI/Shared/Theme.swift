import AppKit
import SwiftUI

/// An sRGB color, components 0 to 1.
nonisolated public struct ThemeRGBA: Sendable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(hex: UInt32, alpha: Double = 1) {
        red = Double(hex >> 16 & 0xFF) / 255
        green = Double(hex >> 8 & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    public var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    var luminance: Double {
        func channel(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}

/// A token with its light and dark values (spec 10.4), and an Increase Contrast value when one
/// differs.
nonisolated public struct ThemeColor: Sendable, Hashable {
    public let light: ThemeRGBA
    public let dark: ThemeRGBA
    public let highContrast: (light: ThemeRGBA, dark: ThemeRGBA)?

    public init(light: UInt32, dark: UInt32, alpha: Double = 1, highContrast: (UInt32, UInt32)? = nil) {
        self.light = ThemeRGBA(hex: light, alpha: alpha)
        self.dark = ThemeRGBA(hex: dark, alpha: alpha)
        self.highContrast = highContrast.map { (ThemeRGBA(hex: $0.0), ThemeRGBA(hex: $0.1)) }
    }

    public static func == (a: ThemeColor, b: ThemeColor) -> Bool { a.light == b.light && a.dark == b.dark }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(light)
        hasher.combine(dark)
    }

    public var nsColor: NSColor {
        let light = light, dark = dark, high = highContrast
        return NSColor(name: nil) { appearance in
            let name = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
            switch name {
            case .darkAqua: return dark.nsColor
            case .accessibilityHighContrastDarkAqua: return (high?.dark ?? dark).nsColor
            case .accessibilityHighContrastAqua: return (high?.light ?? light).nsColor
            default: return light.nsColor
            }
        }
    }

    public var color: Color { Color(nsColor: nsColor) }

    /// The value for a color scheme, for shot mode and drawing code that resolves colors itself.
    public func resolved(_ scheme: ColorScheme) -> ThemeRGBA { scheme == .dark ? dark : light }
}

/// Every color, size, font and motion value Dolly's UI uses (spec 10.4 to 10.6).
nonisolated public enum Theme {
    public static let frame = ThemeColor(light: 0xEFEEEB, dark: 0x0E0E0D)
    public static let sheet = ThemeColor(light: 0xFFFFFF, dark: 0x171716)
    public static let raised = ThemeColor(light: 0xF5F4F1, dark: 0x222120)
    public static let active = ThemeColor(light: 0xE4E2DE, dark: 0x2C2B29)
    public static let border = ThemeColor(light: 0xE6E4E0, dark: 0x2A2928)
    public static let control = ThemeColor(light: 0xCFCCC6, dark: 0x45433F)
    public static let ink = ThemeColor(light: 0x151413, dark: 0xF4F2EE)
    /// Increase Contrast turns secondary text into ink (spec 10.5).
    public static let muted = ThemeColor(light: 0x5E5B57, dark: 0xB0ADA7, highContrast: (0x151413, 0xF4F2EE))
    public static let tape = ThemeColor(light: 0xFF4F9A, dark: 0xFF5FA4)
    public static let onTape = ThemeColor(light: 0x1A0710, dark: 0x1A0710)
    public static let primary = ThemeColor(light: 0x151413, dark: 0xF4F2EE)
    public static let onPrimary = ThemeColor(light: 0xFFFFFF, dark: 0x151413)
    public static let record = ThemeColor(light: 0xD93A2B, dark: 0xFF6B5C)
    /// Outside the zoom's view on the stage in Aim mode.
    public static let scrim = ThemeColor(light: 0x151413, dark: 0x000000, alpha: 0.45)

    public enum Size {
        public static let toolbar: CGFloat = 52
        public static let sidebar: CGFloat = 228
        public static let sheetInset: CGFloat = 8
        public static let sheetRadius: CGFloat = 16
        public static let inspector: CGFloat = 288
        public static let inspectorRadius: CGFloat = 12
        public static let timeline: CGFloat = 322
        public static let margin: CGFloat = 16
        public static let controlRadius: CGFloat = 6
        public static let controlHeight: CGFloat = 28
        /// One choice in a segmented row (inspector tabs, shape bar, pickers).
        public static let segment: CGFloat = 26
        /// A backdrop swatch in the Look tab: six to a row in the 288 pt panel.
        public static let swatch: CGFloat = 36
        public static let poster = CGSize(width: 56, height: 40)
        public static let windowMinimum = CGSize(width: 1100, height: 720)
        /// The tape outline on the window the Record bar will record.
        public static let targetStroke: CGFloat = 3
        public static let targetRadius: CGFloat = 12
        /// The corner card after a recording: how far it slides in, and the clear room for its shadow.
        public static let cardSlide: CGFloat = 16
        public static let cardShadowRoom: CGFloat = 24
    }

    public enum Font {
        /// Avenir Next Demi Bold for the take name, panel titles and tape labels.
        public static func display(_ size: CGFloat) -> SwiftUI.Font { .custom("AvenirNext-DemiBold", size: size) }
        public static let body = SwiftUI.Font.system(size: 13)
        public static let bodyMedium = SwiftUI.Font.system(size: 13, weight: .medium)
        public static let meta = SwiftUI.Font.system(size: 12)
        public static let tick = SwiftUI.Font.system(size: 11)
    }

    public enum Motion {
        public static let press = 0.12
        public static let stripBridge = 0.16
        public static let countdown = 0.2
        public static let saved = 0.16
        /// The corner card enters from the screen edge and leaves the same way.
        public static let cardIn = 0.24
        public static let cardOut = 0.18
    }

    /// WCAG contrast ratio of two colors.
    public static func contrast(_ a: ThemeRGBA, _ b: ThemeRGBA) -> Double {
        let la = a.luminance, lb = b.luminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
