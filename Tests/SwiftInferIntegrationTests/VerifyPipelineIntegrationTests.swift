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
        let outcome = try Self.runPipeline(
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

    // MARK: - V1.44.E.3 idempotence × {Complex<Double>, Double, Int}

    /// Build + run the idempotence verify pipeline against the supplied
    /// single-function call expression on the given carrier. Mirrors
    /// `runPipeline` but uses `IdempotenceStubEmitter` so the stub
    /// asserts `f(f(x)) ≈ f(x)` (or `f(f(x)) == f(x)` for Int).
    private static func runIdempotencePipeline(
        functionCall: String,
        carrierType: String,
        budget: IdempotenceStubEmitter.TrialBudget = .small
    ) throws -> VerifyOutcome {
        let workdir = try makeWorkdir()
        defer { cleanUp(workdir) }
        let stubSource = try IdempotenceStubEmitter.emit(
            IdempotenceStubEmitter.Inputs(
                functionCall: functionCall,
                extraImports: [],
                carrierType: carrierType,
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

    /// **V1.44.E.3.a — idempotence × Complex<Double> × edgeCaseAdvisory.**
    /// `f(z) = z.isFinite ? Complex(1, 0) : Complex(0, 0)` is idempotent
    /// on finite values (`f(z) = Complex(1, 0)`; `f(f(z)) = Complex(1, 0)`),
    /// and on non-finite values returns `Complex(0, 0)` once but
    /// `Complex(1, 0)` on the second application — `f(f(z)) ≠ f(z)`
    /// when the input is one of curated entries #0–#7 (the non-finite
    /// ones). The default pass samples only finite values (Double.random
    /// in ±1e6) so it passes 100/100; the edge pass fires on the first
    /// non-finite curated entry sampled and reports `.edgeCaseAdvisory`
    /// with `edgeCaseIndex ∈ [0, 7]`.
    @Test("idempotence × Complex<Double>: finite-only property fires advisory on non-finite entry")
    func idempotenceComplexDoubleEdgeCaseAdvisory() throws {
        let outcome = try Self.runIdempotencePipeline(
            functionCall:
                "{ (zedValue: Complex<Double>) in "
                + "zedValue.isFinite ? Complex(1, 0) : Complex(0, 0) }",
            carrierType: "Complex<Double>"
        )
        if case let .edgeCaseAdvisory(defaultTrials, _, _, _, _, edgeCaseIndex) = outcome {
            #expect(defaultTrials == 100)
            // First failing edge trial is one of the 8 non-finite
            // curated entries — index resolves to [0, 7] via the
            // `.rawStorage` match.
            #expect((0...7).contains(edgeCaseIndex))
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
        let outcome = try Self.runIdempotencePipeline(
            functionCall: "{ (xValue: Double) in xValue * 2 }",
            carrierType: "Double"
        )
        if case .defaultFails = outcome {
            // Edge pass skipped by short-circuit; per-field
            // counterexample data depends on the RNG-sampled value
            // so we only pin the case.
        } else {
            Issue.record("expected .defaultFails; got \(outcome)")
        }
    }

    /// **V1.44.E.3.c — idempotence × Int × bothPass.** Identity
    /// `{ x in x }` over `Int` — `f(f(x)) = x = f(x)` for every
    /// integer input. Int carrier emits a zero-edge sentinel
    /// (`VERIFY_EDGE_TRIALS: 0`), so the parser produces
    /// `.bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0)`.
    @Test("idempotence × Int: identity passes single-pass (zero-edge sentinel)")
    func idempotenceIntBothPassSingleSentinel() throws {
        let outcome = try Self.runIdempotencePipeline(
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

    // MARK: - V1.45.E.3 commutativity × {Complex<Double>, Double, Int}

    /// Build + run the commutativity verify pipeline against the
    /// supplied two-argument function-call expression on the given
    /// carrier. Mirrors `runIdempotencePipeline` but uses
    /// `CommutativityStubEmitter` so the stub asserts `f(a, b) ≈
    /// f(b, a)` (or `f(a, b) == f(b, a)` for Int).
    private static func runCommutativityPipeline(
        functionCall: String,
        carrierType: String,
        budget: CommutativityStubEmitter.TrialBudget = .small
    ) throws -> VerifyOutcome {
        let workdir = try makeWorkdir()
        defer { cleanUp(workdir) }
        let stubSource = try CommutativityStubEmitter.emit(
            CommutativityStubEmitter.Inputs(
                functionCall: functionCall,
                extraImports: [],
                carrierType: carrierType,
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

    /// **V1.45.E.3.a — commutativity × Complex<Double> × bothPass.**
    /// `{ (a, b) in a + b }` over `Complex<Double>` is commutative on
    /// the finite domain (`a + b == b + a` componentwise) and on the
    /// non-finite "point at infinity" (swift-numerics' Complex `==`
    /// collapses all non-finite values to one equivalence class, so
    /// `f(non-finite, finite) == f(finite, non-finite)` trivially).
    /// Pipeline reports `.bothPass` with `edgeTrials > 0` and a
    /// non-zero `edgeSampled` count over 100 trials.
    @Test("commutativity × Complex<Double>: a+b is commutative across both passes")
    func commutativityComplexDoubleBothPass() throws {
        let outcome = try Self.runCommutativityPipeline(
            functionCall: "{ (a: Complex<Double>, b: Complex<Double>) in a + b }",
            carrierType: "Complex<Double>"
        )
        if case let .bothPass(defaultTrials, edgeTrials, edgeSampled) = outcome {
            #expect(defaultTrials == 100)
            #expect(edgeTrials == 100)
            // edgeSampled is deterministic at a fixed seed but RNG-state-
            // arithmetic dependent; pin the kit's [0, 12] curated-entry
            // range contract.
            #expect((0...12).contains(edgeSampled))
        } else {
            Issue.record("expected .bothPass; got \(outcome)")
        }
    }

    /// **V1.45.E.3.b — commutativity × Double × defaultFails.**
    /// `{ (a, b) in a - b }` is non-commutative for every unequal
    /// pair: `a - b == b - a` only when `a == b`. The default
    /// generator samples in ±1e6 with probability of equal pairs
    /// vanishingly small (~1/2^53), so the first trial fires.
    /// Edge pass is skipped by the runner's short-circuit.
    @Test("commutativity × Double: a-b is non-commutative; fails default pass at trial 0")
    func commutativityDoubleDefaultFails() throws {
        let outcome = try Self.runCommutativityPipeline(
            functionCall: "{ (a: Double, b: Double) in a - b }",
            carrierType: "Double"
        )
        if case .defaultFails = outcome {
            // Edge pass skipped by short-circuit per proposal §2.2 row 3;
            // per-field counterexample data is RNG-dependent so we only
            // pin the case.
        } else {
            Issue.record("expected .defaultFails; got \(outcome)")
        }
    }

    /// **V1.45.E.3.c — commutativity × Int × bothPass.** Int addition
    /// `{ (a, b) in a + b }` is commutative; the Int carrier emits
    /// the V1.44.B/C zero-edge sentinel so the parser produces
    /// `.bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0)`.
    @Test("commutativity × Int: a+b is commutative (zero-edge sentinel)")
    func commutativityIntBothPassSingleSentinel() throws {
        let outcome = try Self.runCommutativityPipeline(
            functionCall: "{ (a: Int, b: Int) in a + b }",
            carrierType: "Int"
        )
        if case let .bothPass(defaultTrials, edgeTrials, edgeSampled) = outcome {
            #expect(defaultTrials == 100)
            #expect(edgeTrials == 0)
            #expect(edgeSampled == 0)
        } else {
            Issue.record("expected .bothPass; got \(outcome)")
        }
    }
}
