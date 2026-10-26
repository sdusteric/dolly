import Testing
@testable import DollyUI

@Suite struct SmokeTests {
    @Test func moduleLoads() { #expect(Bool(true)) }
}
