import SwiftInferCore

// The per-carrier / per-signature-shape reducer-CALL emission, extracted from
// ActionSequenceStubEmitter.swift to keep that file under SwiftLint's
// file_length cap. `makeApplyStep` is the loop-step call; the post-loop
// idempotence double-apply lives in `+FamilyChecks`.
extension ActionSequenceStubEmitter {

    /// One iteration of the action-application loop. Returns the statement(s)
    /// that mutate `state` for the given carrier + signature shape:
    ///   - `.tca` — instance-relative `reducer.reduce(into:&state, action:)`.
    ///   - `.mobius` — `update(state, action) -> Next<Model, Effect>`; the new
    ///     model is `next.model` (nil = `.noChange` → keep state).
    ///   - ReSwift (`actionFirst`) — `reducer(action, state)` (reversed args).
    ///   - else — the canonical shape-based call.
    /// Effect-bearing shapes (M8.A) discard the returned effect (PRD §16 #1).
    /// Returned as an array so the assembler appends each line at the caller's
    /// indent depth.
    static func makeApplyStep(
        shape: ReducerSignatureShape,
        reducerCall: String,
        isTCA: Bool = false,
        actionFirst: Bool = false,
        isMobius: Bool = false
    ) -> [String] {
        if isTCA {
            return ["_ = reducer.reduce(into: &state, action: action)"]
        }
        if isMobius {
            return [
                "let next = \(reducerCall)(state, action)",
                "if let mobiusModel = next.model { state = mobiusModel }"
            ]
        }
        switch shape {
        case .stateActionReturnsState:
            return ["state = \(reducerCall)(\(orderedArgs("state", "action", actionFirst: actionFirst)))"]

        case .inoutStateActionReturnsVoid:
            return ["\(reducerCall)(&state, action)"]

        case .stateActionReturnsStateAndEffect:
            return [
                "let (newState, _) = \(reducerCall)(state, action)",
                "state = newState"
            ]

        case .inoutStateActionReturnsEffect:
            return ["_ = \(reducerCall)(&state, action)"]
        }
    }
}
