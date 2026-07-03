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
        isMobius: Bool = false
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

        case .idempotence:
            return []

        // Determinism is a per-step check, not a single-witness post-loop one:
        // it must hold for EVERY action, so it runs on the loop's current
        // `(state, action)` — two fresh applications, compared.
        case .determinism:
            return makeDeterminismCheck(
                shape: shape,
                reducerCall: reducerCall,
                isTCA: isTCA,
                actionFirst: actionFirst,
                isMobius: isMobius
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
        isMobius: Bool = false
    ) -> [String] {
        guard let invariant else { return [] }
        switch invariant.family {
        // Determinism runs as a per-step check (see makePerStepCheck).
        case .conservation, .cardinality, .referentialIntegrity, .biconditional, .determinism:
            return []

        case .idempotence:
            return makeIdempotenceCheck(
                actionExpr: invariant.predicate,
                shape: shape,
                reducerCall: reducerCall,
                isTCA: isTCA,
                actionFirst: actionFirst,
                isMobius: isMobius
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
        isMobius: Bool = false
    ) -> [String] {
        let assertion =
            "precondition(once == twice, "
                + "\"Idempotence invariant violated for \(actionExpr)\")"
        // Mobius: double-apply the witness, taking `Next.model` each time
        // (nil = `.noChange` → keep the prior model). Effects discarded.
        if isMobius {
            return [
                "let once = \(reducerCall)(state, \(actionExpr)).model ?? state",
                "let twice = \(reducerCall)(once, \(actionExpr)).model ?? once",
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
        switch shape {
        case .stateActionReturnsState:
            return [
                "let once = \(reducerCall)(\(orderedArgs("state", actionExpr, actionFirst: actionFirst)))",
                "let twice = \(reducerCall)(\(orderedArgs("once", actionExpr, actionFirst: actionFirst)))",
                assertion
            ]

        case .inoutStateActionReturnsVoid:
            return [
                "var once = state",
                "\(reducerCall)(&once, \(actionExpr))",
                "var twice = once",
                "\(reducerCall)(&twice, \(actionExpr))",
                assertion
            ]

        case .stateActionReturnsStateAndEffect:
            return [
                "let (once, _) = \(reducerCall)(state, \(actionExpr))",
                "let (twice, _) = \(reducerCall)(once, \(actionExpr))",
                assertion
            ]

        case .inoutStateActionReturnsEffect:
            return [
                "var once = state",
                "_ = \(reducerCall)(&once, \(actionExpr))",
                "var twice = once",
                "_ = \(reducerCall)(&twice, \(actionExpr))",
                assertion
            ]
        }
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
        isMobius: Bool = false
    ) -> [String] {
        let assertion =
            "precondition(detFirst == detSecond, "
                + "\"Determinism invariant violated\")"
        if isMobius {
            return [
                "let detFirst = \(reducerCall)(state, action).model ?? state",
                "let detSecond = \(reducerCall)(state, action).model ?? state",
                assertion
            ]
        }
        if isTCA {
            return [
                "var detFirst = state",
                "_ = reducer.reduce(into: &detFirst, action: action)",
                "var detSecond = state",
                "_ = reducer.reduce(into: &detSecond, action: action)",
                assertion
            ]
        }
        switch shape {
        case .stateActionReturnsState:
            return [
                "let detFirst = \(reducerCall)(\(orderedArgs("state", "action", actionFirst: actionFirst)))",
                "let detSecond = \(reducerCall)(\(orderedArgs("state", "action", actionFirst: actionFirst)))",
                assertion
            ]

        case .inoutStateActionReturnsVoid:
            return [
                "var detFirst = state",
                "\(reducerCall)(&detFirst, action)",
                "var detSecond = state",
                "\(reducerCall)(&detSecond, action)",
                assertion
            ]

        case .stateActionReturnsStateAndEffect:
            return [
                "let (detFirst, _) = \(reducerCall)(state, action)",
                "let (detSecond, _) = \(reducerCall)(state, action)",
                assertion
            ]

        case .inoutStateActionReturnsEffect:
            return [
                "var detFirst = state",
                "_ = \(reducerCall)(&detFirst, action)",
                "var detSecond = state",
                "_ = \(reducerCall)(&detSecond, action)",
                assertion
            ]
        }
    }
}
