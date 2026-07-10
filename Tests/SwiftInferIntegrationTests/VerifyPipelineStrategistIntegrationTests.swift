import Foundation
import SwiftInferCLI
import SwiftInferCore
import Testing

/// V1.89 lint pass — `strategist`-routed arm of the verify-pipeline
/// integration suite. Split from
/// `VerifyPipelineIntegrationTests.swift` so each suite stays under
/// SwiftLint's 350-line `type_body_length` cap. All tests use the
/// shared `VerifyPipelineIntegrationFixture` helpers.
@Suite("Verify pipeline — strategist integration", .tags(.subprocess))
struct VerifyPipelineStrategistIntegrationTests {

    @Test("strategist × Int × idempotence: identity passes single-pass")
    func strategistIntIdempotenceBothPass() throws {
        let outcome = try VerifyPipelineIntegrationFixture.runStrategistPipeline(
            functionCalls: ["{ (value: Int) in value }"],
            carrier: "Int",
            template: "idempotence"
        )
        if case let .bothPass(defaultTrials, edgeTrials, edgeSampled) = outcome {
            #expect(defaultTrials == 100)
            #expect(edgeTrials == 0)
            #expect(edgeSampled == 0)
        } else {
            Issue.record("expected .bothPass; got \(outcome)")
        }
    }

    /// **V1.47.G.6.b — strategist × String × idempotence × bothPass.**
    /// Identity function on `String` via the strategist's direct-RawType
    /// fast path. Confirms the new carrier surface beyond v1.46's
    /// `{Complex<Double>, Double, Int}` works end-to-end.
    @Test("strategist × String × idempotence: identity passes single-pass")
    func strategistStringIdempotenceBothPass() throws {
        let outcome = try VerifyPipelineIntegrationFixture.runStrategistPipeline(
            functionCalls: ["{ (value: String) in value }"],
            carrier: "String",
            template: "idempotence"
        )
        if case let .bothPass(defaultTrials, edgeTrials, edgeSampled) = outcome {
            #expect(defaultTrials == 100)
            #expect(edgeTrials == 0)
            #expect(edgeSampled == 0)
        } else {
            Issue.record("expected .bothPass; got \(outcome)")
        }
    }

    /// **V1.47.G.6.c — strategist × bound generic carrier × idempotence
    /// × bothPass.** Simulates the cycle-27 chunked-Index path
    /// post-GenericBindingResolver: `Base.Index` would resolve to
    /// `Int`. The test directly emits with `carrier: "Int"` (the
    /// resolved form) and an identity function; this exercises the
    /// same strategist code path the verify harness takes after the
    /// resolver fires.
    @Test("strategist × bound carrier (Int via Base.Index) × idempotence: identity passes")
    func strategistBoundCarrierIdempotenceBothPass() throws {
        // Sanity: confirm the binding resolver actually maps Base.Index → Int.
        #expect(GenericBindingResolver.bound("Base.Index") == "Int")
        // Run with the bound carrier name — same code path the harness
        // takes post-rebound.
        let outcome = try VerifyPipelineIntegrationFixture.runStrategistPipeline(
            functionCalls: ["{ (idx: Int) in idx }"],
            carrier: GenericBindingResolver.bound("Base.Index"),
            template: "idempotence"
        )
        if case .bothPass = outcome {
            // Success — bound carrier flows through the strategist
            // single-pass path identically to a literal Int carrier.
        } else {
            Issue.record("expected .bothPass; got \(outcome)")
        }
    }

    /// **V1.47.G.6.d — strategist × `.todo` strategy → fallback path.**
    /// A struct typeShape with a non-stdlib stored-property type
    /// trips the strategist's `.todo` branch
    /// (`Cannot derive a generator for ...`). The
    /// `StrategistDispatchEmitter` translates that into a
    /// `VerifyError.unsupportedCarrier`, which the V1.47.F router
    /// catches and falls back to the v1.46 hardcoded path. Since
    /// neither carrier matches the v1.46 set either, the final
    /// emit throws — this test pins that throw at the emitter level
    /// (not subprocess), avoiding a deliberately failed build.
    @Test("strategist × .todo strategy → emitter throws .unsupportedCarrier")
    func strategistTodoFallback() throws {
        let shape = IndexedTypeShape(
            name: "Unsupported",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: [
                IndexedTypeShape.StoredMember(name: "x", typeName: "Widget")
            ],
            hasUserInit: false
        )
        #expect(throws: VerifyError.self) {
            _ = try StrategistDispatchEmitter.emit(
                StrategistDispatchEmitter.Inputs(
                    carrier: "Unsupported",
                    typeShape: shape,
                    template: "idempotence",
                    functionCalls: ["{ (x: Unsupported) in x }"],
                    extraImports: [],
                    seedHex: VerifyPipelineIntegrationFixture.canonicalSeed,
                    trialBudget: .small
                )
            )
        }
    }

    /// **v1.141 — strategist × Int × monotonicity × shrink.** Negation
    /// `{ n in -n }` is anti-monotone (`a ≤ b ⇒ f(a) ≥ f(b)`), so the property
    /// fails; the `Int` carrier is shrinkable, so the gated shrink phase
    /// compiles + runs and minimizes the failing pair.
    @Test("strategist × Int × monotonicity: anti-monotone -n shrinks the failing pair")
    func strategistIntMonotonicityShrinks() throws {
        let outcome = try VerifyPipelineIntegrationFixture.runStrategistPipeline(
            functionCalls: ["{ (value: Int) in -value }"],
            carrier: "Int",
            template: "monotonicity"
        )
        guard case let .defaultFails(detail) = outcome else {
            Issue.record("expected .defaultFails; got \(outcome)")
            return
        }
        #expect(detail.shrink != nil)
    }

    /// **v1.141 — strategist × Int × round-trip × shrink-to-0.** This is the
    /// real-CLI path for Int (Route 2). `n + 1` / `n` fails everywhere and
    /// the single-input shrink minimizes deterministically to 0.
    @Test("strategist × Int × round-trip: n+1 shrinks to 0")
    func strategistIntRoundTripShrinksToZero() throws {
        let outcome = try VerifyPipelineIntegrationFixture.runStrategistPipeline(
            functionCalls: ["{ (value: Int) in value &+ 1 }", "{ (value: Int) in value }"],
            carrier: "Int",
            template: "round-trip"
        )
        guard case let .defaultFails(detail) = outcome else {
            Issue.record("expected .defaultFails; got \(outcome)")
            return
        }
        let shrink = try #require(detail.shrink)
        #expect(shrink.minimal == "0")
    }

    /// **v1.141 — strategist × Int × commutativity × pair-shrink.** `a - b`
    /// is non-commutative; exercises the strategist pair-shrink end-to-end.
    @Test("strategist × Int × commutativity: a-b shrinks the failing pair")
    func strategistIntCommutativityShrinks() throws {
        let outcome = try VerifyPipelineIntegrationFixture.runStrategistPipeline(
            functionCalls: ["{ (aVal: Int, bVal: Int) in aVal &- bVal }"],
            carrier: "Int",
            template: "commutativity"
        )
        guard case let .defaultFails(detail) = outcome else {
            Issue.record("expected .defaultFails; got \(outcome)")
            return
        }
        #expect(detail.shrink != nil)
    }

    /// **v1.141 — strategist × Int × associativity × triple-shrink.** `a - b`
    /// is non-associative; exercises the strategist triple-shrink end-to-end.
    @Test("strategist × Int × associativity: a-b shrinks the failing triple")
    func strategistIntAssociativityShrinks() throws {
        let outcome = try VerifyPipelineIntegrationFixture.runStrategistPipeline(
            functionCalls: ["{ (aVal: Int, bVal: Int) in aVal &- bVal }"],
            carrier: "Int",
            template: "associativity"
        )
        guard case let .defaultFails(detail) = outcome else {
            Issue.record("expected .defaultFails; got \(outcome)")
            return
        }
        #expect(detail.shrink != nil)
    }
}
