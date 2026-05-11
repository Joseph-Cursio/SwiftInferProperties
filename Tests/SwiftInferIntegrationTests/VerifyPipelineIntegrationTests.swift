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

    /// **V1.42.D.2 — known-good integration.** Identity round-trip:
    /// `forward = inverse = { z in z }`. `inverse(forward(value)) ==
    /// value` exactly. Pipeline should report `.pass(trials: 100)`.
    @Test("known-good identity round-trip passes 100 trials")
    func knownGoodIdentityRoundTrip() throws {
        let outcome = try Self.runPipeline(
            forwardCall: "{ (zedValue: Complex<Double>) in zedValue }",
            inverseCall: "{ (zedValue: Complex<Double>) in zedValue }"
        )
        #expect(outcome == .pass(trials: 100))
    }

    // MARK: - D.3 known-bad

    /// **V1.42.D.3 — known-bad integration.** Asymmetric pair:
    /// `forward = { z in z + 1 }`, `inverse = { z in z }`.
    /// `inverse(forward(value)) = value + 1 ≠ value` for any input.
    /// Pipeline should report `.fail` at trial 0 (the very first
    /// random sample fires the counterexample).
    @Test("known-bad asymmetric round-trip fails at trial 0")
    func knownBadAsymmetricRoundTrip() throws {
        let outcome = try Self.runPipeline(
            forwardCall: "{ (zedValue: Complex<Double>) in zedValue + Complex(1, 0) }",
            inverseCall: "{ (zedValue: Complex<Double>) in zedValue }"
        )
        if case .fail = outcome {
            // Outcome is .fail — the per-field counterexample data
            // is non-deterministic (depends on RNG-sampled value),
            // so we only pin the case here.
        } else {
            Issue.record("expected .fail; got \(outcome)")
        }
    }
}
