import Foundation
import SwiftInferCore

// V2.0 — `makePerStepCheck` / `makePostLoopCheck` / `makeIdempotenceCheck`
// lifted out of the main file via extension so the parent enum's body
// stays under SwiftLint's `type_body_length` cap. Pure relocation — no
// behavior change. Same pattern as the M8.A `+Types.swift` split.

extension ActionSequenceStubEmitter {

    /// V2.0 M4.D / M5 / M6 — per-step invariant check
    /// (Conservation + Cardinality + Referential Integrity). Three
    /// families embed a boolean predicate evaluated at each action
    /// step. Idempotence uses the post-loop double-apply check
    /// instead.
    static func makePerStepCheck(
        invariant: InteractionInvariantSuggestion?,
        shape: ReducerSignatureShape = .stateActionReturnsState,
        reducerCall: String = "reduce",
        isTCA: Bool = false,
        actionFirst: Bool = false,
        isMobius: Bool = false,
        isAsync: Bool = false
    ) -> [String] {
        guard let invariant else { return [] }
        switch invariant.family {
        case .conservation:
            return [
                "precondition(\(invariant.predicate), "
                    + "\"Conservation invariant violated\")"
            ]

        case .cardinality:
            return [
                "precondition(\(invariant.predicate), "
                    + "\"Cardinality invariant violated\")"
            ]

        case .referentialIntegrity:
            return [
                "precondition(\(invariant.predicate), "
                    + "\"Referential-integrity invariant violated\")"
            ]

        case .biconditional:
            return [
                "precondition(\(invariant.predicate), "
                    + "\"Biconditional invariant violated\")"
            ]

        // Idempotence and unknown-action-is-no-op are single-witness post-loop
        // checks, not per-step ones.
        case .idempotence, .unknownActionIsNoOp:
            return []

        // outputDeterminism is verified by OutputDeterminismVerifierEmitter, not
        // this reducer emitter. It must be routed away before emit; if it isn't,
        // trap loudly rather than emit a vacuously-passing stub.
        case .outputDeterminism:
            return [
                "precondition(false, \"output-determinism uses a dedicated "
                    + "recording-fake verifier, not the action-sequence emitter\")"
            ]

        // Determinism is a per-step check, not a single-witness post-loop one:
        // it must hold for EVERY action, so it runs on the loop's current
        // `(state, action)` — two fresh applications, compared.
        case .determinism:
            return makeDeterminismCheck(
                shape: shape,
                reducerCall: reducerCall,
                isTCA: isTCA,
                actionFirst: actionFirst,
                isMobius: isMobius,
                isAsync: isAsync
            )
        }
    }

    /// V2.0 M4.D — post-loop invariant check (Idempotence). After
    /// the action sequence has driven `state` to a varied position,
    /// applies the candidate action twice and asserts state-equality.
    /// Branches on `signatureShape` because `(inout S, A) -> Void`
    /// needs a copy-and-mutate dance vs. `(S, A) -> S`'s direct
    /// assignment. Returns empty for nil invariant or non-Idempotence
    /// families.
    static func makePostLoopCheck(
        invariant: InteractionInvariantSuggestion?,
        shape: ReducerSignatureShape,
        reducerCall: String,
        isTCA: Bool = false,
        actionFirst: Bool = false,
        isMobius: Bool = false,
        isAsync: Bool = false
    ) -> [String] {
        guard let invariant else { return [] }
        switch invariant.family {
        // Determinism runs as a per-step check (see makePerStepCheck);
        // outputDeterminism is verified by its own harness, not here.
        case .conservation, .cardinality, .referentialIntegrity, .biconditional,
             .determinism, .outputDeterminism:
            return []

        case .idempotence:
            return makeIdempotenceCheck(
                actionExpr: invariant.predicate,
                shape: shape,
                reducerCall: reducerCall,
                isTCA: isTCA,
                actionFirst: actionFirst,
                isMobius: isMobius,
                isAsync: isAsync
            )

        case .unknownActionIsNoOp:
            return makeUnknownActionCheck(
                shape: shape,
                reducerCall: reducerCall,
                actionFirst: actionFirst,
                isMobius: isMobius,
                isAsync: isAsync
            )
        }
    }

    /// The two-argument list for a `(State, Action)` reducer call,
    /// reversed to `(Action, State)` for ReSwift (`actionFirst`). Only the
    /// value-returning `.stateActionReturnsState` shape uses this — the
    /// `inout` shapes pass `&state` and aren't a ReSwift carrier.
    static func orderedArgs(_ state: String, _ action: String, actionFirst: Bool) -> String {
        actionFirst ? "\(action), \(state)" : "\(state), \(action)"
    }

    /// V2.0 M4.D / M8.A — the idempotence check body, parameterized
    /// over the signature shape. Pulled to a static so tests can
    /// drive the body shape independently of the surrounding stub.
    /// M8.A extends with two effect-bearing arms: the `Effect<A>`
    /// half of the tuple / return is **captured and discarded** per
    /// PRD §16 #1 (swift-infer never runs user-side Effects).
    static func makeIdempotenceCheck(
        actionExpr: String,
        shape: ReducerSignatureShape,
        reducerCall: String,
        isTCA: Bool = false,
        actionFirst: Bool = false,
        isMobius: Bool = false,
        isAsync: Bool = false
    ) -> [String] {
        let awaitPrefix = isAsync ? "await " : ""
        let assertion =
            "precondition(once == twice, "
                + "\"Idempotence invariant violated for \(actionExpr)\")"
        // Mobius: double-apply the witness, taking `Next.model` each time
        // (nil = `.noChange` → keep the prior model). Effects discarded.
        if isMobius {
            return [
                "let once = \(awaitPrefix)\(reducerCall)(state, \(actionExpr)).model ?? state",
                "let twice = \(awaitPrefix)\(reducerCall)(once, \(actionExpr)).model ?? once",
                assertion
            ]
        }
        // Cycle 122 (Phase A) — `.tca` double-applies the witness through
        // the instance reducer; Effects discarded (PRD §16 #1).
        if isTCA {
            return [
                "var once = state",
                "_ = reducer.reduce(into: &once, action: \(actionExpr))",
                "var twice = once",
                "_ = reducer.reduce(into: &twice, action: \(actionExpr))",
                assertion
            ]
        }
        return idempotenceShapeCheck(
            actionExpr: actionExpr,
            shape: shape,
            reducerCall: reducerCall,
            actionFirst: actionFirst,
            awaitPrefix: awaitPrefix,
            assertion: assertion
        )
    }

    /// The canonical-shape arms of `makeIdempotenceCheck`, split out to keep
    /// that function under SwiftLint's `function_body_length` cap (the async
    /// `awaitPrefix` line-wraps pushed it over).
    private static func idempotenceShapeCheck(
        actionExpr: String,
        shape: ReducerSignatureShape,
        reducerCall: String,
        actionFirst: Bool = false,
        awaitPrefix: String,
        assertion: String
    ) -> [String] {
        switch shape {
        case .stateActionReturnsState:
            return [
                "let once = \(awaitPrefix)\(reducerCall)"
                    + "(\(orderedArgs("state", actionExpr, actionFirst: actionFirst)))",
                "let twice = \(awaitPrefix)\(reducerCall)"
                    + "(\(orderedArgs("once", actionExpr, actionFirst: actionFirst)))",
                assertion
            ]

        case .inoutStateActionReturnsVoid:
            return [
                "var once = state",
                "\(awaitPrefix)\(reducerCall)(&once, \(actionExpr))",
                "var twice = once",
                "\(awaitPrefix)\(reducerCall)(&twice, \(actionExpr))",
                assertion
            ]

        case .stateActionReturnsStateAndEffect:
            return [
                "let (once, _) = \(awaitPrefix)\(reducerCall)(state, \(actionExpr))",
                "let (twice, _) = \(awaitPrefix)\(reducerCall)(once, \(actionExpr))",
                assertion
            ]

        case .inoutStateActionReturnsEffect:
            return [
                "var once = state",
                "_ = \(awaitPrefix)\(reducerCall)(&once, \(actionExpr))",
                "var twice = once",
                "_ = \(awaitPrefix)\(reducerCall)(&twice, \(actionExpr))",
                assertion
            ]
        }
    }

    /// Dependency-pinned TCA determinism (docs/tca-determinism-verify-scope.md):
    /// with declared `@Dependencies` fixed to constant values, two applications
    /// of the same `(state, action)` must be equal. Any residual difference is
    /// UN-declared nondeterminism — a raw `Date()` / `UUID()` / `Set`-order in
    /// the state mutation instead of a `@Dependency` — the TCA anti-pattern this
    /// catches. The pins return stable values on repeated reads, so one shared
    /// scope is deterministic across both calls; all are available via
    /// `import ComposableArchitecture`. (`withRandomNumberGenerator` deferred —
    /// it needs a seedable RNG emitted into the stub.)
    static func tcaDeterminismCheck(assertion: String) -> [String] {
        [
            "withDependencies {",
            "    $0.date = .constant(Date(timeIntervalSince1970: 0))",
            "    $0.uuid = .constant("
                + "UUID(uuidString: \"00000000-0000-0000-0000-000000000000\")!)",
            "    $0.calendar = Calendar(identifier: .gregorian)",
            "    $0.timeZone = TimeZone(secondsFromGMT: 0)!",
            "    $0.continuousClock = ImmediateClock()",
            "    $0.suspendingClock = ImmediateClock()",
            "} operation: {",
            "    var detFirst = state",
            "    _ = reducer.reduce(into: &detFirst, action: action)",
            "    var detSecond = state",
            "    _ = reducer.reduce(into: &detSecond, action: action)",
            "    \(assertion)",
            "}"
        ]
    }

    /// V2.0 Phase 2 (Redux) — the determinism check body: two INDEPENDENT
    /// applications of the loop's current `action` to the current `state`,
    /// asserted equal (`reduce(s, a) == reduce(s, a)`). Unlike idempotence
    /// (which double-applies a fixed *witness* action post-loop), determinism
    /// must hold for every action, so it runs per-step on the loop variables
    /// `state` + `action`. Shape/carrier handling mirrors
    /// `makeIdempotenceCheck`. A hidden `Date()` / `UUID()` / `.random()`
    /// makes the two applications differ → `precondition` traps →
    /// `measuredDefaultFails`, which static purity analysis cannot catch.
    static func makeDeterminismCheck(
        shape: ReducerSignatureShape,
        reducerCall: String,
        isTCA: Bool = false,
        actionFirst: Bool = false,
        isMobius: Bool = false,
        isAsync: Bool = false
    ) -> [String] {
        let awaitPrefix = isAsync ? "await " : ""
        let assertion =
            "precondition(detFirst == detSecond, "
                + "\"Determinism invariant violated\")"
        if isMobius {
            return [
                "let detFirst = \(awaitPrefix)\(reducerCall)(state, action).model ?? state",
                "let detSecond = \(awaitPrefix)\(reducerCall)(state, action).model ?? state",
                assertion
            ]
        }
        if isTCA {
            return tcaDeterminismCheck(assertion: assertion)
        }
        switch shape {
        case .stateActionReturnsState:
            return [
                "let detFirst = \(awaitPrefix)\(reducerCall)"
                    + "(\(orderedArgs("state", "action", actionFirst: actionFirst)))",
                "let detSecond = \(awaitPrefix)\(reducerCall)"
                    + "(\(orderedArgs("state", "action", actionFirst: actionFirst)))",
                assertion
            ]

        case .inoutStateActionReturnsVoid:
            return [
                "var detFirst = state",
                "\(awaitPrefix)\(reducerCall)(&detFirst, action)",
                "var detSecond = state",
                "\(awaitPrefix)\(reducerCall)(&detSecond, action)",
                assertion
            ]

        case .stateActionReturnsStateAndEffect:
            return [
                "let (detFirst, _) = \(awaitPrefix)\(reducerCall)(state, action)",
                "let (detSecond, _) = \(awaitPrefix)\(reducerCall)(state, action)",
                assertion
            ]

        case .inoutStateActionReturnsEffect:
            return [
                "var detFirst = state",
                "_ = \(awaitPrefix)\(reducerCall)(&detFirst, action)",
                "var detSecond = state",
                "_ = \(awaitPrefix)\(reducerCall)(&detSecond, action)",
                assertion
            ]
        }
    }

    /// V2.0 — the unknown-action-is-no-op post-loop check. Applies a freshly
    /// minted probe action (a type conforming to the reducer's *open* Action
    /// alphabet, declared at file scope by `assembleStub`) to the current
    /// state and asserts State is unchanged: `reduce(s, unknown) == s`. Open
    /// alphabets have no generatable actions, so the sequence loop runs empty
    /// and this checks the initial state. Effect halves are discarded (PRD
    /// §16 #1). Shape/carrier handling mirrors `makeIdempotenceCheck`.
    static func makeUnknownActionCheck(
        shape: ReducerSignatureShape,
        reducerCall: String,
        actionFirst: Bool = false,
        isMobius: Bool = false,
        isAsync: Bool = false
    ) -> [String] {
        let awaitPrefix = isAsync ? "await " : ""
        let probe = "\(Self.unknownActionProbeTypeName)()"
        let assertion =
            "precondition(afterProbe == state, "
                + "\"unknown-action-is-no-op invariant violated: reduce(s, unknown) != s\")"
        if isMobius {
            return [
                "let afterProbe = \(awaitPrefix)\(reducerCall)(state, \(probe)).model ?? state",
                assertion
            ]
        }
        switch shape {
        case .stateActionReturnsState:
            return [
                "let afterProbe = \(awaitPrefix)\(reducerCall)"
                    + "(\(orderedArgs("state", probe, actionFirst: actionFirst)))",
                assertion
            ]

        case .inoutStateActionReturnsVoid:
            return [
                "var afterProbe = state",
                "\(awaitPrefix)\(reducerCall)(&afterProbe, \(probe))",
                assertion
            ]

        case .stateActionReturnsStateAndEffect:
            return [
                "let (afterProbe, _) = \(awaitPrefix)\(reducerCall)(state, \(probe))",
                assertion
            ]

        case .inoutStateActionReturnsEffect:
            return [
                "var afterProbe = state",
                "_ = \(awaitPrefix)\(reducerCall)(&afterProbe, \(probe))",
                assertion
            ]
        }
    }
}
