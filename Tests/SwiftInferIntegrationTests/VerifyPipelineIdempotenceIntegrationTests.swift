import Foundation
import SwiftInferCLI
import SwiftInferCore
import Testing

/// V1.89 lint pass — `idempotence` arm of the verify-pipeline
/// integration suite. Split from
/// `VerifyPipelineIntegrationTests.swift` so each suite stays under
/// SwiftLint's 350-line `type_body_length` cap. All tests use the
/// shared `VerifyPipelineIntegrationFixture` helpers.
@Suite("Verify pipeline — idempotence integration", .tags(.subprocess))
struct VerifyPipelineIdempotenceTests {

    @Test("idempotence × Complex<Double>: finite-only property fires advisory on non-finite entry")
    func idempotenceComplexDoubleEdgeCaseAdvisory() throws {
        let outcome = try VerifyPipelineIntegrationFixture.runIdempotencePipeline(
            functionCall:
                "{ (zedValue: Complex<Double>) in "
                + "zedValue.isFinite ? Complex(1, 0) : Complex(0, 0) }",
            carrierType: "Complex<Double>"
        )
        if case let .edgeCaseAdvisory(defaultTrials, edge) = outcome {
            #expect(defaultTrials == 100)
            // First failing edge trial is one of the 8 non-finite
            // curated entries — index resolves to [0, 7] via the
            // `.rawStorage` match.
            #expect((0...7).contains(edge.caseIndex))
        } else {
            Issue.record("expected .edgeCaseAdvisory; got \(outcome)")
        }
    }

    /// **V1.44.E.3.b — idempotence × Double × defaultFails.**
    /// `f(x) = x * 2` is non-idempotent on every non-zero input:
    /// `f(f(x)) = 4x ≠ 2x = f(x)`. Default pass samples in ±1e6 so
    /// the first non-zero sample fires the counterexample. Edge pass
    /// is skipped by the runner's short-circuit.
    @Test("idempotence × Double: non-idempotent f(x) = 2x fails default pass at trial 0")
    func idempotenceDoubleDefaultFails() throws {
        let outcome = try VerifyPipelineIntegrationFixture.runIdempotencePipeline(
            functionCall: "{ (xValue: Double) in xValue * 2 }",
            carrierType: "Double"
        )
        guard case let .defaultFails(detail) = outcome else {
            Issue.record("expected .defaultFails; got \(outcome)")
            return
        }
        // v1.141: the shrink phase compiled + ran and emitted its markers.
        #expect(detail.shrink != nil)
    }

    /// **v1.141 — idempotence × Int × shrink-to-0.** `f(n) = n + 1` is
    /// non-idempotent everywhere (`f(f(n)) = n + 2 ≠ n + 1`), including 0,
    /// so the shrink phase minimizes deterministically to 0.
    @Test("idempotence × Int: non-idempotent f(n) = n + 1 shrinks to 0")
    func idempotenceIntShrinksToZero() throws {
        let outcome = try VerifyPipelineIntegrationFixture.runIdempotencePipeline(
            functionCall: "{ (xValue: Int) in xValue &+ 1 }",
            carrierType: "Int"
        )
        guard case let .defaultFails(detail) = outcome else {
            Issue.record("expected .defaultFails; got \(outcome)")
            return
        }
        let shrink = try #require(detail.shrink)
        #expect(shrink.minimal == "0")
        #expect(shrink.steps >= 1)
    }

    /// **V1.44.E.3.c — idempotence × Int × bothPass.** Identity
    /// `{ x in x }` over `Int` — `f(f(x)) = x = f(x)` for every
    /// integer input. Int carrier emits a zero-edge sentinel
    /// (`VERIFY_EDGE_TRIALS: 0`), so the parser produces
    /// `.bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0)`.
    @Test("idempotence × Int: identity passes single-pass (zero-edge sentinel)")
    func idempotenceIntBothPassSingleSentinel() throws {
        let outcome = try VerifyPipelineIntegrationFixture.runIdempotencePipeline(
            functionCall: "{ (xValue: Int) in xValue }",
            carrierType: "Int"
        )
        if case let .bothPass(defaultTrials, edgeTrials, edgeSampled) = outcome {
            #expect(defaultTrials == 100)
            // Int carrier sentinel — V1.44.B/C convention.
            #expect(edgeTrials == 0)
            #expect(edgeSampled == 0)
        } else {
            Issue.record("expected .bothPass; got \(outcome)")
        }
    }

    /// **Real-axis edge-set idempotence × Double × bothPass.** `abs` is
    /// idempotent on every real, including all nine curated edge cases
    /// (`abs(abs(x)) == abs(x)` for NaN/±Inf/±0/overflow/subnormal under
    /// the NaN-reflexive oracle). The edge pass therefore reaches a
    /// verdict and samples MULTIPLE distinct curated entries — the guard
    /// that the widened real-axis set is live end-to-end: the prior
    /// NaN-only set could sample at most 1.
    @Test("idempotence × Double: abs samples multiple real-axis edge cases (bothPass)")
    func idempotenceDoubleRealAxisEdgeSampling() throws {
        let outcome = try VerifyPipelineIntegrationFixture.runIdempotencePipeline(
            functionCall: "abs",
            carrierType: "Double"
        )
        if case let .bothPass(defaultTrials, edgeTrials, edgeSampled) = outcome {
            #expect(defaultTrials == 100)
            #expect(edgeTrials == 100)
            // > 1 is impossible under the old NaN-only edge set; <= 9 is
            // the curated real-axis count.
            #expect(edgeSampled > 1)
            #expect(edgeSampled <= 9)
        } else {
            Issue.record("expected .bothPass; got \(outcome)")
        }
    }
}
