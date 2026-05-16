import Foundation
import SwiftInferCLI
import SwiftInferCore
import Testing

/// V1.42.D — end-to-end verify-pipeline integration tests (round-trip
/// arm).
///
/// **Always-on per `swift test`.** Each test spawns a real
/// `swift build` + verifier-binary run, adding ~5-15s of build time
/// per case. Acceptable cost given the load-bearing nature of the
/// verify pipeline. The user-facing exit conditions are pinned via
/// the C.4 parser → renderer flow.
///
/// **Fixtures use IIFE-shaped call expressions.** The C.2 stub
/// concatenates `forwardCall` and `inverseCall` with `(value)` /
/// `(forwardResult)`, so any expression that yields a callable
/// works. `{ (z: Complex<Double>) in <expr> }` is the cleanest
/// shape — no user-package fixture needed; the verifier workdir
/// depends only on swift-numerics + swift-property-based.
///
/// **V1.89 lint pass:** the original 21-test struct exceeded
/// SwiftLint's 350-line `type_body_length` cap. Idempotence /
/// commutativity / associativity / strategist / lifted-and-friends
/// tests live in sibling files; shared helpers live in
/// `VerifyPipelineIntegrationFixture`.
@Suite("Verify pipeline — V1.42.D end-to-end integration", .tags(.subprocess))
struct VerifyPipelineIntegrationTests {

    /// **V1.43-extended known-good integration.** Identity round-trip:
    /// `forward = inverse = { z in z }`. `inverse(forward(value)) ==
    /// value` exactly across both default and edge-case-biased passes
    /// (identity holds for NaN, ±Inf, ±0, etc.). Pipeline should
    /// report `.bothPass(defaultTrials: 100, edgeTrials: 100, edgeSampled:
    /// <0...12>)`. Identity is in scope here because every edge case
    /// is its own approximate-equal (`isApproximatelyEqual` returns
    /// true for `nan ≈ nan` via Complex's NaN-aware override; the kit
    /// verifies this in PropertyLawComplex's distribution test).
    @Test("known-good identity round-trip passes both passes")
    func knownGoodIdentityRoundTrip() throws {
        let outcome = try VerifyPipelineIntegrationFixture.runPipeline(
            forwardCall: "{ (zedValue: Complex<Double>) in zedValue }",
            inverseCall: "{ (zedValue: Complex<Double>) in zedValue }"
        )
        if case let .bothPass(defaultTrials, edgeTrials, edgeSampled) = outcome {
            #expect(defaultTrials == 100)
            #expect(edgeTrials == 100)
            // edgeSampled is deterministic at a fixed seed but depends
            // on Pass 1's RNG-state arithmetic — pin only the [0, 12]
            // contract from the kit's curated-entry count.
            #expect((0...12).contains(edgeSampled))
        } else {
            Issue.record("expected .bothPass; got \(outcome)")
        }
    }

    // MARK: - D.3 known-bad

    /// **V1.43-extended known-bad integration.** Asymmetric pair:
    /// `forward = { z in z + 1 }`, `inverse = { z in z }`.
    /// `inverse(forward(value)) = value + 1 ≠ value` for any input.
    /// Pipeline should report `.defaultFails` at trial 0 (the very
    /// first random sample fires the counterexample); the edge pass
    /// is skipped by the runner's short-circuit per proposal §2.2 row 3.
    @Test("known-bad asymmetric round-trip fails default pass at trial 0")
    func knownBadAsymmetricRoundTrip() throws {
        let outcome = try VerifyPipelineIntegrationFixture.runPipeline(
            forwardCall: "{ (zedValue: Complex<Double>) in zedValue + Complex(1, 0) }",
            inverseCall: "{ (zedValue: Complex<Double>) in zedValue }"
        )
        if case .defaultFails = outcome {
            // Outcome is .defaultFails — the per-field counterexample
            // data is non-deterministic (depends on RNG-sampled value),
            // so we only pin the case here. Edge pass is skipped by
            // the runner's short-circuit; nothing further to assert.
        } else {
            Issue.record("expected .defaultFails; got \(outcome)")
        }
    }

    // MARK: - E.3.b edge-case-advisory

    /// **V1.43.E.3.b — edge-case-advisory integration.** Property that
    /// holds for finite inputs but breaks on non-finite ones:
    /// `forward = { z in z.isFinite ? z : Complex(0, 0) }`,
    /// `inverse = { z in z }`.
    ///
    /// The default pass uses `Double.random(in: -1e6...1e6)` so it
    /// only ever samples finite Complex values, and the property
    /// is identity on finite values — Pass 1 always passes.
    ///
    /// The edge pass samples the kit's curated 12-entry set. Entries
    /// #0–#7 are non-finite (NaN / ±Inf in at least one component);
    /// entries #8–#11 are finite (`Complex(0, 0)`, `Complex(-0.0, 0)`,
    /// `Complex(greatestFiniteMagnitude, 0)`,
    /// `Complex(leastNonzeroMagnitude, 0)`). The property fails on the
    /// first non-finite entry sampled, fires `.edgeCaseAdvisory`, and
    /// the runner's `.rawStorage`-based `matchEdgeCaseIndex` resolves
    /// the index into `[0, 7]`.
    @Test("edge-case advisory: finite-only property fires on first non-finite curated entry")
    func edgeCaseAdvisoryOnNonFiniteEntry() throws {
        let outcome = try VerifyPipelineIntegrationFixture.runPipeline(
            forwardCall:
                "{ (zedValue: Complex<Double>) in "
                + "zedValue.isFinite ? zedValue : Complex(0, 0) }",
            inverseCall: "{ (zedValue: Complex<Double>) in zedValue }"
        )
        if case let .edgeCaseAdvisory(defaultTrials, _, _, _, _, edgeCaseIndex) = outcome {
            #expect(defaultTrials == 100)
            // The first failing trial is determined by the kit's
            // seeded `Gen<Int>.int(in: 0 ..< 120)` tag sequence; at
            // a fixed seed the resolved index is deterministic but
            // depends on Pass 1's RNG-state arithmetic. We pin the
            // contract that it must be one of the 8 non-finite
            // curated entries (#0–#7). A value of -1 here would
            // indicate the property failed on a finite-slice
            // non-curated value, which the property by construction
            // can never do.
            #expect((0...7).contains(edgeCaseIndex))
        } else {
            Issue.record("expected .edgeCaseAdvisory; got \(outcome)")
        }
    }

}
