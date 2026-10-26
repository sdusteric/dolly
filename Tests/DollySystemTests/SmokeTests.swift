import Testing
@testable import DollySystem

@Suite struct SmokeTests {
    @Test func moduleLoads() { #expect(Bool(true)) }
}
