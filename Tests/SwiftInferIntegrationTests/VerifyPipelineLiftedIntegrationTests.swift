import Foundation
import SwiftInferCLI
import SwiftInferCore
import Testing

/// V1.89 lint pass — lifted / dual-style / monotonicity / memberwise
/// / non-curated round-trip arms of the verify-pipeline integration
/// suite. Split from `VerifyPipelineIntegrationTests.swift` so each
/// suite stays under SwiftLint's 350-line `type_body_length` cap.
/// All tests use the shared `VerifyPipelineIntegrationFixture`
/// helpers.
@Suite("Verify pipeline — lifted + dual-style + monotonicity + memberwise integration", .tags(.subprocess))
struct VerifyPipelineLiftedIntegrationTests {

    @Test("idempotence-lifted × Int: sorted() is idempotent over [Int]")
    func idempotenceLiftedIntBothPass() throws {
        let outcome = try VerifyPipelineIntegrationFixture.runStrategistPipeline(
            functionCalls: ["{ (xs: [Int]) in xs.sorted() }"],
            carrier: "Int",
            template: "idempotence-lifted"
        )
        if case let .bothPass(defaultTrials, edgeTrials, edgeSampled) = outcome {
            #expect(defaultTrials == 100)
            #expect(edgeTrials == 0)
            #expect(edgeSampled == 0)
        } else {
            Issue.record("expected .bothPass; got \(outcome)")
        }
    }

    /// **V1.48.H.2 / V1.49.F.1 — dual-style-consistency × Int × bothPass.**
    /// V1.49.A's stub-preamble channel unblocks this test. The
    /// preamble injects `extension Int { mutating func bumpInPlace()
    /// { self += 1 } }` plus a `nonMutBump(_:) -> Int` helper. The
    /// dual-style-consistency check then asserts
    /// `nonMutBump(x) == { var c = x; c.bumpInPlace(); c }()` —
    /// trivially true by construction. Carrier "Int" routes through
    /// the strategist's direct-RawType fast path.
    @Test("dual-style-consistency × Int (V1.49.F.1): bumpInPlace/nonMutBump pair")
    func dualStyleConsistencyIntBothPass() throws {
        let preamble = """
        extension Int {
            mutating func bumpInPlace() { self += 1 }
        }
        func nonMutBump(_ value: Int) -> Int { value + 1 }
        """
        let workdir = try VerifyPipelineIntegrationFixture.makeWorkdir()
        defer { VerifyPipelineIntegrationFixture.cleanUp(workdir) }
        let stubSource = try StrategistDispatchEmitter.emit(
            StrategistDispatchEmitter.Inputs(
                carrier: "Int",
                typeShape: nil,
                template: "dual-style-consistency",
                functionCalls: ["nonMutBump", "bumpInPlace"],
                extraImports: [],
                seedHex: VerifyPipelineIntegrationFixture.canonicalSeed,
                trialBudget: .small,
                preamble: preamble
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
            Issue.record("build failed: \(buildOutput.stderr)")
            return
        }
        let runOutput = try VerifierSubprocess.runVerifierBinary(workdir: workdir)
        let outcome = VerifyResultParser.parse(runOutput)
        if case .bothPass = outcome {
            // Success — preamble injects the type extension; nonMut/mut
            // pair is consistent by construction.
        } else {
            Issue.record("expected .bothPass; got \(outcome)")
        }
    }

    /// **V1.48.H.3 — monotonicity × Int × bothPass.**
    /// `{ x in x + 1 }` is monotone-increasing on Int. The V1.48.A
    /// composer draws 2 values, sorts via min/max so a ≤ b, asserts
    /// f(a) ≤ f(b). The strategist's `Gen<Int>.int()` defaults to
    /// `.min ... .max` (per swift-property-based 1.2.x), so
    /// `x + 1` overflow-traps only at `x == Int.max` — probability
    /// ~100/2^64 over 100 trials, effectively zero. Operations like
    /// `x * 2` would overflow ~50% of trials and crash; `x + 1` is
    /// the canonical overflow-safe monotone function for this test
    /// shape.
    @Test("monotonicity × Int: x → x+1 is monotone-increasing")
    func monotonicityIntBothPass() throws {
        let outcome = try VerifyPipelineIntegrationFixture.runStrategistPipeline(
            functionCalls: ["{ (x: Int) in x + 1 }"],
            carrier: "Int",
            template: "monotonicity"
        )
        if case let .bothPass(defaultTrials, edgeTrials, edgeSampled) = outcome {
            #expect(defaultTrials == 100)
            #expect(edgeTrials == 0)
            #expect(edgeSampled == 0)
        } else {
            Issue.record("expected .bothPass; got \(outcome)")
        }
    }

    /// **V1.49.F.2 — strategist × 2-member-struct × idempotence × bothPass.**
    /// Preamble injects a 2-member `Pair` struct definition; the
    /// strategist's `.memberwiseArbitrary` strategy (V1.49.B) emits
    /// `zip(Gen<Int>.int(), Gen<Int>.int()).map { (m0, m1) in
    /// Pair(x: m0, y: m1) }`. Idempotence check on the identity
    /// function `{ p in p }` is trivially `.bothPass`.
    @Test("memberwise × 2-member-struct × idempotence (V1.49.F.2)")
    func memberwise2MemberIdempotenceBothPass() throws {
        let preamble = """
        struct PairCarrier: Equatable, Sendable {
            let x: Int
            let y: Int
        }
        """
        let workdir = try VerifyPipelineIntegrationFixture.makeWorkdir()
        defer { VerifyPipelineIntegrationFixture.cleanUp(workdir) }
        let typeShape = IndexedTypeShape(
            name: "PairCarrier",
            kind: .struct,
            inheritedTypes: ["Equatable", "Sendable"],
            hasUserGen: false,
            storedMembers: [
                IndexedTypeShape.StoredMember(name: "x", typeName: "Int"),
                IndexedTypeShape.StoredMember(name: "y", typeName: "Int")
            ],
            hasUserInit: false
        )
        let stubSource = try StrategistDispatchEmitter.emit(
            StrategistDispatchEmitter.Inputs(
                carrier: "PairCarrier",
                typeShape: typeShape,
                template: "idempotence",
                functionCalls: ["{ (p: PairCarrier) in p }"],
                extraImports: [],
                seedHex: VerifyPipelineIntegrationFixture.canonicalSeed,
                trialBudget: .small,
                preamble: preamble
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
            Issue.record("build failed: \(buildOutput.stderr)")
            return
        }
        let runOutput = try VerifierSubprocess.runVerifierBinary(workdir: workdir)
        let outcome = VerifyResultParser.parse(runOutput)
        if case .bothPass = outcome {
            // V1.49.B's memberwise emit + V1.49.A's preamble channel
            // together let the strategist build a generator for a
            // user-defined value-typed struct in the workdir.
        } else {
            Issue.record("expected .bothPass; got \(outcome)")
        }
    }

    /// **V1.49.F.3 — non-curated round-trip pair × Int × bothPass.**
    /// Carrier "Int" + a forward/inverse pair that's NOT in
    /// `RoundTripPairResolver.curated` (e.g. `bumped(_:)` /
    /// `unbumped(_:)`). The resolver falls back to
    /// `entry.secondaryFunctionName`. Preamble defines both halves
    /// as free functions; round-trip stub calls
    /// `Int.bumped(value)` (via the strategist) and inversely.
    ///
    /// **Implementation note**: the verify pipeline resolves
    /// expressions as `<typeQualifier>.<funcName>`, so for an Int
    /// carrier the call becomes `Int.bumped(_:)` / `Int.unbumped(_:)`.
    /// We don't define those — we use a closure-based forward/inverse
    /// pair directly through the stub source.
    @Test("non-curated round-trip pair × Int (V1.49.F.3)")
    func nonCuratedRoundTripIntBothPass() throws {
        // No preamble needed — the closures are passed directly as
        // function-call expressions and don't reference any
        // user-defined names.
        let workdir = try VerifyPipelineIntegrationFixture.makeWorkdir()
        defer { VerifyPipelineIntegrationFixture.cleanUp(workdir) }
        let stubSource = try StrategistDispatchEmitter.emit(
            StrategistDispatchEmitter.Inputs(
                carrier: "Int",
                typeShape: nil,
                template: "round-trip",
                functionCalls: [
                    "{ (x: Int) in x + 100 }",
                    "{ (x: Int) in x - 100 }"
                ],
                extraImports: [],
                seedHex: VerifyPipelineIntegrationFixture.canonicalSeed,
                trialBudget: .small
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
            Issue.record("build failed: \(buildOutput.stderr)")
            return
        }
        let runOutput = try VerifierSubprocess.runVerifierBinary(workdir: workdir)
        let outcome = VerifyResultParser.parse(runOutput)
        if case .bothPass = outcome {
            // Strategist's round-trip composer takes the forward/inverse
            // pair directly from `functionCalls[0]` / `[1]`; this is the
            // *emit-side* of V1.49.C's non-curated pair derivation.
            // The *resolve-side* (entry.secondaryFunctionName) is
            // exercised in the unit-test suite (V149SecondaryFunctionNameTests).
        } else {
            Issue.record("expected .bothPass; got \(outcome)")
        }
    }
}
