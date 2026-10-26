import Testing
@testable import DollyCore

@Suite struct TimeTextTests {
    @Test func clockFormats() {
        #expect(TimeText.clock(8.6) == "0:08.6")
        #expect(TimeText.clock(48.2) == "0:48.2")
        #expect(TimeText.clock(3725) == "1:02:05.0")
        #expect(TimeText.clock(59.96) == "1:00.0")
    }

    @Test func secondsAndShort() {
        #expect(TimeText.seconds(2.7) == "2.7 s")
        #expect(TimeText.short(48.2) == "0:48")
        #expect(TimeText.short(72.6) == "1:13")
    }
}
