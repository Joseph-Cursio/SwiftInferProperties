import Foundation
import SwiftInferCLI
import Testing

/// v1.141 — end-to-end compile-and-run validation of the round-trip shrink
/// phase for the non-Complex carriers (Int, Double). These use the
/// `value.shrink(towards: 0)` API shape, distinct from the Complex carrier's
/// per-component `.real`/`.imaginary` shrink (covered by
/// `VerifyPipelineIntegrationTests.knownBadAsymmetricRoundTrip`).
///
/// Each test synthesizes a verifier workdir, runs a real `swift build` + the
/// verifier binary, and asserts the emitted shrink loop both **compiles** and
/// **runs**: a known-bad `forward = { x in x + 1 }`, `inverse = { x in x }`
/// fails every trial, so the shrink phase minimizes toward 0.
@Suite("Verify pipeline — v1.141 round-trip shrink (Int/Double)", .tags(.subprocess))
struct VerifyPipelineRoundTripShrinkIntegrationTests {

    @Test("Int known-bad round-trip shrinks the counterexample to 0")
    func intRoundTripShrinksToZero() throws {
        let outcome = try VerifyPipelineIntegrationFixture.runPipeline(
            forwardCall: "{ (intValue: Int) in intValue &+ 1 }",
            inverseCall: "{ (intValue: Int) in intValue }",
            carrierType: "Int"
        )
        guard case let .defaultFails(detail) = outcome else {
            Issue.record("expected .defaultFails; got \(outcome)")
            return
        }
        // The shrink phase ran (compiled + executed) and emitted its markers.
        let shrink = try #require(detail.shrink)
        // `n.shrink(towards: 0)` yields 0 first, which still fails (0 + 1 ≠ 0),
        // so the minimal counterexample is deterministically 0.
        #expect(shrink.minimal == "0")
        #expect(shrink.steps >= 1)
    }

    @Test("Double known-bad round-trip shrinks the counterexample toward 0")
    func doubleRoundTripShrinks() throws {
        let outcome = try VerifyPipelineIntegrationFixture.runPipeline(
            forwardCall: "{ (doubleValue: Double) in doubleValue + 1 }",
            inverseCall: "{ (doubleValue: Double) in doubleValue }",
            carrierType: "Double"
        )
        guard case let .defaultFails(detail) = outcome else {
            Issue.record("expected .defaultFails; got \(outcome)")
            return
        }
        // The shrink phase compiled + executed and emitted its markers; the
        // minimal still fails the round-trip.
        let shrink = try #require(detail.shrink)
        #expect(shrink.steps >= 1)
    }
}
