import Foundation
import SwiftInferCLI
import SwiftInferCore
import Testing

/// V1.89 lint pass — `commutativity` + `associativity` arms of the
/// verify-pipeline integration suite. Split from
/// `VerifyPipelineIntegrationTests.swift` so each suite stays under
/// SwiftLint's 350-line `type_body_length` cap. All tests use the
/// shared `VerifyPipelineIntegrationFixture` helpers.
@Suite("Verify pipeline — commutativity + associativity integration", .tags(.subprocess))
struct VerifyPipelineCommAssocIntegrationTests {

    @Test("commutativity × Complex<Double>: a+b is commutative across both passes")
    func commutativityComplexDoubleBothPass() throws {
        let outcome = try VerifyPipelineIntegrationFixture.runCommutativityPipeline(
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
        let outcome = try VerifyPipelineIntegrationFixture.runCommutativityPipeline(
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
        let outcome = try VerifyPipelineIntegrationFixture.runCommutativityPipeline(
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

    // MARK: - V1.46.D.4 associativity × {Complex<Double>, Double, Int}

    /// **V1.46.D.4.a — associativity × Complex<Double> × bothPass.**
    /// `{ (a, b) in a + b }` over `Complex<Double>` is associative on
    /// the finite domain (componentwise IEEE 754 addition associates
    /// within `isApproximatelyEqual` tolerance) and on the non-finite
    /// point-at-infinity equivalence class. Pipeline reports
    /// `.bothPass` with `edgeTrials == 100` and a non-zero
    /// `edgeSampled` count under per-slot edge rotation.
    @Test("associativity × Complex<Double>: a+b is associative across both passes")
    func associativityComplexDoubleBothPass() throws {
        let outcome = try VerifyPipelineIntegrationFixture.runAssociativityPipeline(
            functionCall: "{ (a: Complex<Double>, b: Complex<Double>) in a + b }",
            carrierType: "Complex<Double>"
        )
        if case let .bothPass(defaultTrials, edgeTrials, edgeSampled) = outcome {
            #expect(defaultTrials == 100)
            #expect(edgeTrials == 100)
            #expect((0...12).contains(edgeSampled))
        } else {
            Issue.record("expected .bothPass; got \(outcome)")
        }
    }

    /// **V1.46.D.4.b — associativity × Double × defaultFails.**
    /// `{ (a, b) in a - b }` is non-associative: `(a − b) − c = a − b − c`
    /// vs `a − (b − c) = a − b + c`, differing by `2c`. For random
    /// nonzero `c` in ±1e6 the relative difference is far above
    /// `isApproximatelyEqual` tolerance; the first trial fires.
    @Test("associativity × Double: a-b is non-associative; fails default pass at trial 0")
    func associativityDoubleDefaultFails() throws {
        let outcome = try VerifyPipelineIntegrationFixture.runAssociativityPipeline(
            functionCall: "{ (a: Double, b: Double) in a - b }",
            carrierType: "Double"
        )
        if case .defaultFails = outcome {
            // Edge pass skipped by short-circuit per proposal §2.2 row 3.
        } else {
            Issue.record("expected .defaultFails; got \(outcome)")
        }
    }

    /// **V1.46.D.4.c — associativity × Int × bothPass.** Int addition
    /// `{ (a, b) in a + b }` is associative; the Int carrier emits
    /// the V1.44.B/C zero-edge sentinel so the parser produces
    /// `.bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0)`.
    @Test("associativity × Int: a+b is associative (zero-edge sentinel)")
    func associativityIntBothPassSingleSentinel() throws {
        let outcome = try VerifyPipelineIntegrationFixture.runAssociativityPipeline(
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
