import Foundation
import SwiftInferCLI
import Testing

/// V1.42.D — end-to-end verify-pipeline integration tests.
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
@Suite("Verify pipeline — V1.42.D end-to-end integration")
struct VerifyPipelineIntegrationTests {

    // MARK: - Helpers

    private static func makeWorkdir() throws -> URL {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("verify-pipeline-integration")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }

    private static func cleanUp(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static let canonicalSeed = RoundTripStubEmitter.SeedHex(
        stateA: 0x01,
        stateB: 0x02,
        stateC: 0x03,
        stateD: 0x04
    )

    /// Build + run a synthesized verifier workdir against the given
    /// pair of call expressions. Returns the parsed outcome so the
    /// test can assert against it.
    private static func runPipeline(
        forwardCall: String,
        inverseCall: String,
        budget: RoundTripStubEmitter.TrialBudget = .small
    ) throws -> VerifyOutcome {
        let workdir = try makeWorkdir()
        defer { cleanUp(workdir) }
        let stubSource = try RoundTripStubEmitter.emit(
            RoundTripStubEmitter.Inputs(
                forwardCall: forwardCall,
                inverseCall: inverseCall,
                extraImports: [],
                carrierType: "Complex<Double>",
                seedHex: canonicalSeed,
                trialBudget: budget
            )
        )
        _ = try VerifierWorkdir.synthesize(
            VerifierWorkdir.Inputs(
                workdir: workdir,
                userPackage: nil,
                stubSource: stubSource
            )
        )
        let buildOutput = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
        guard buildOutput.exitCode == 0 else {
            return .error(reason: "build failed: \(buildOutput.stderr)")
        }
        let runOutput = try VerifierSubprocess.runVerifierBinary(workdir: workdir)
        return VerifyResultParser.parse(runOutput)
    }

    // MARK: - D.2 known-good

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
        let outcome = try Self.runPipeline(
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
        let outcome = try Self.runPipeline(
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
}
