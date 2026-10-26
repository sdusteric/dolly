import Testing
@testable import DollyUI

@Suite struct ThemeTests {
    let textPairs: [(String, ThemeColor, ThemeColor)] = [
        ("ink on sheet", Theme.ink, Theme.sheet), ("muted on sheet", Theme.muted, Theme.sheet),
        ("muted on frame", Theme.muted, Theme.frame), ("muted on raised", Theme.muted, Theme.raised),
        ("ink on active", Theme.ink, Theme.active), ("on tape on tape", Theme.onTape, Theme.tape),
        ("on primary on primary", Theme.onPrimary, Theme.primary),
    ]

    @Test func everyTextPairPassesContrast() {
        for (name, fg, bg) in textPairs {
            #expect(Theme.contrast(fg.light, bg.light) >= 4.5, "\(name) light")
            #expect(Theme.contrast(fg.dark, bg.dark) >= 4.5, "\(name) dark")
        }
    }

    @Test func tapeMarkPassesNonText() {
        #expect(Theme.contrast(Theme.tape.light, Theme.sheet.light) >= 3.0)
        #expect(Theme.contrast(Theme.tape.dark, Theme.sheet.dark) >= 3.0)
    }

    @Test func tokensMatchTheSpec() {
        #expect(Theme.tape.light == ThemeRGBA(hex: 0xFF4F9A) && Theme.frame.dark == ThemeRGBA(hex: 0x0E0E0D))
        #expect(Theme.Size.sidebar == 228 && Theme.Size.toolbar == 52 && Theme.Size.inspector == 288)
        #expect(Theme.Motion.press == 0.12 && Theme.Motion.stripBridge == 0.16)
    }
}
