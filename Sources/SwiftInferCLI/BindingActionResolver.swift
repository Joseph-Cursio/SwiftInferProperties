import Foundation
import SwiftInferCore

/// Item 2 slice 4 — resolve a `.tca` reducer's `case binding(BindingAction<State>)`
/// action against its own `@ObservableState` State fields, so Phase B's relaxed
/// exploration can construct a `BindingAction.set(\.field, value)` value.
///
/// **Simpler than slice 3.** `BindingAction<State>` binds the reducer's *own*
/// State, so resolution needs no cross-candidate lookup — just the candidate's
/// captured `stateFields` (populated only for `@ObservableState` States, which
/// is the gate for the modern `.set(\.field, value)` keypath form; legacy
/// `@BindingState` reducers use `\.$field` and stay excluded). A binding case
/// resolves to *every* stored `var` whose type is cheaply defaultable
/// (`Bool` / `Int` / `String` / `Double` / `UUID`), and the emitter explores
/// binding each of them (`Gen.oneOf` when there is more than one).
///
/// **Unlike slice 3b, a binding action drives a real transition** — `.set`
/// writes the value into State via `BindingReducer` — so this exercises the
/// binding path, not just widening the disclosed action space.
enum BindingActionResolver {

    /// Field value types the verifier can construct a canned literal for.
    static let defaultableValueTypes: Set<String> = ["Bool", "Int", "String", "Double", "UUID"]

    /// Enrich `candidate`'s `binding(BindingAction<State>)` case with the
    /// defaultable bindable fields. Returns the candidate unchanged when it's
    /// non-`.tca`, has no observable State fields, or has no binding case.
    static func resolve(_ candidate: ReducerCandidate) -> ReducerCandidate {
        guard candidate.carrierKind == .tca, !candidate.stateFields.isEmpty else { return candidate }
        let bindableFields = candidate.stateFields
            .filter { defaultableValueTypes.contains($0.typeName) }
            .map { ResolvedBindingField(fieldName: $0.name, valueType: $0.typeName) }
        guard !bindableFields.isEmpty else { return candidate }

        var changed = false
        let newCases = candidate.actionCases.map { caseInfo -> ActionCaseInfo in
            guard caseInfo.resolvedBinding == nil,
                  caseInfo.payloadTypes.count == 1,
                  isBindingActionPayload(caseInfo.payloadTypes[0])
            else { return caseInfo }
            changed = true
            return ActionCaseInfo(
                name: caseInfo.name,
                payloadTypes: caseInfo.payloadTypes,
                resolvedElement: caseInfo.resolvedElement,
                resolvedBinding: bindableFields
            )
        }
        guard changed else { return candidate }
        return candidate.replacingActionCases(newCases)
    }

    /// `true` for a `BindingAction<...>` payload (the modern
    /// `case binding(BindingAction<State>)` shape).
    static func isBindingActionPayload(_ payload: String) -> Bool {
        payload.trimmingCharacters(in: .whitespaces).hasPrefix("BindingAction<")
    }
}
