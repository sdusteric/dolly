import Testing
@testable import DollyRender

@Suite struct SmokeTests {
    @Test func moduleLoads() { #expect(Bool(true)) }
}
