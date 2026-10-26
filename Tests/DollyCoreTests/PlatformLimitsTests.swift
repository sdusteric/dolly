import Testing
@testable import DollyCore

@Suite struct PlatformLimitsTests {
    @Test func fitsBoth() { #expect(PlatformLimits.lengthLine(48.2) == "Fits X (2:20 max) and Threads (5:00 max)") }
    @Test func tooLongForX() { #expect(PlatformLimits.lengthLine(152) == "Too long for X by 0:12. Fits Threads (5:00 max)") }
    @Test func tooLongForBoth() { #expect(PlatformLimits.lengthLine(352) == "Too long for X by 3:32 and for Threads by 0:52") }
    @Test func exactlyAtTheLimitFits() { #expect(PlatformLimits.lengthLine(140) == "Fits X (2:20 max) and Threads (5:00 max)") }
}
