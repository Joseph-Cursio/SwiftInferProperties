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
    static func makePerStepCheck(invariant: InteractionInvariantSuggestion?) -> [String] {
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
        reducerCall: String
    ) -> [String] {
        guard let invariant else { return [] }
        switch invariant.family {
        case .conservation, .cardinality, .referentialIntegrity, .biconditional:
            return []
        case .idempotence:
            return makeIdempotenceCheck(
                actionExpr: invariant.predicate,
                shape: shape,
                reducerCall: reducerCall
            )
        }
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
        reducerCall: String
    ) -> [String] {
        let assertion =
            "precondition(once == twice, "
                + "\"Idempotence invariant violated for \(actionExpr)\")"
        switch shape {
        case .stateActionReturnsState:
            return [
                "let once = \(reducerCall)(state, \(actionExpr))",
                "let twice = \(reducerCall)(once, \(actionExpr))",
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
}
