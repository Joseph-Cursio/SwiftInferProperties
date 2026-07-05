import Foundation
import PropertyLawCore
import SwiftInferCore

// Cycle 125 (Phase B) — Action-case constructibility + the `.tca` action
// generator, lifted out of ActionSequenceStubEmitter.swift via extension so the
// primary file stays under SwiftLint's file-length cap (same split pattern as
// +FamilyChecks.swift / +Types.swift / +UnknownAction.swift). Item 2 widens the
// constructible subset here (composition-wrapper payloads).

extension ActionSequenceStubEmitter {

    /// The constructible Action cases — payload-free, a single associated value
    /// of a recognized raw type, or a recognized composition wrapper. These are
    /// what the relaxed generator explores; everything else (multi-value or
    /// non-raw, non-wrapper payloads) is excluded and disclosed.
    static func constructibleCases(_ candidate: ReducerCandidate) -> [ActionCaseInfo] {
        candidate.actionCases.filter {
            $0.payloadTypes.isEmpty
                || rawGenerator(for: $0) != nil
                || compositionGenerator(for: $0, action: candidate.actionTypeName) != nil
        }
    }

    /// A generator expression for a single-payload case whose payload is a
    /// recognized TCA composition wrapper the verifier can construct a canonical
    /// value for **without deriving the wrapped type** — or nil when the case
    /// isn't a recognized wrapper. This widens Phase B's constructible subset
    /// beyond payload-free + raw-scalar cases, under the same relaxed
    /// partial-exploration posture (the excluded set is still disclosed).
    ///
    /// Slice 1 — `PresentationAction<T>`: emit the payload-free `.dismiss` case,
    /// so `case alert(PresentationAction<Alert>)` explores `Action.alert(.dismiss)`
    /// with no `Gen<Alert>` needed. `.dismiss` drives the reducer's presentation
    /// dismissal path — a real, constructible transition.
    ///
    /// Slice 2 — `Result<_, any Error>`: emit `.failure(CancellationError())` — a
    /// canned type-erased error, no `Gen<Success>` needed — driving the reducer's
    /// failure branch. Gated to the *type-erased* error forms (`, any Error>` /
    /// `, Error>`); a concrete error type (`Result<T, MyError>`) is left excluded
    /// because `CancellationError()` would not conform to it.
    static func compositionGenerator(for caseInfo: ActionCaseInfo, action: String) -> String? {
        // Slice 3 — a resolved `IdentifiedActionOf<Child>` element. The
        // resolver (`IdentifiedActionResolver`) has already looked up the child
        // reducer and confirmed a defaultable id + a payload-free child case;
        // here we only format the canned id literal + the `.element(id:action:)`
        // expression. The constructed element **no-ops against the empty
        // initial-State `IdentifiedArray`** (`.forEach` finds no element with
        // the canned id) — so this widens the explored action space (fewer
        // disclosed `excluded:` cases) without new counterexample signal, per
        // the slice-3 design's ROI reframe.
        if let element = caseInfo.resolvedElement {
            guard let idLiteral = defaultValueLiteral(for: element.idType) else { return nil }
            return "Gen.always(\(action).\(caseInfo.name)(.element(id: \(idLiteral)"
                + ", action: \(element.childActionType).\(element.childActionCase))))"
        }
        // Slice 4 — a resolved `binding(BindingAction<State>)` case. The
        // resolver has enumerated the reducer's `@ObservableState` stored `var`
        // fields whose type is cheaply defaultable; explore binding each one
        // (`.set(\.field, <canned value>)` — a real transition through
        // `BindingReducer`). One field → `Gen.always`; several → `Gen.oneOf`.
        if let fields = caseInfo.resolvedBinding, !fields.isEmpty {
            let sets = fields.compactMap { field -> String? in
                guard let literal = defaultValueLiteral(for: field.valueType) else { return nil }
                return "Gen.always(\(action).\(caseInfo.name)(.set(\\.\(field.fieldName), \(literal))))"
            }
            guard !sets.isEmpty else { return nil }
            return sets.count == 1 ? sets[0] : "Gen.oneOf(\(sets.joined(separator: ", ")))"
        }
        guard caseInfo.payloadTypes.count == 1 else { return nil }
        let payload = caseInfo.payloadTypes[0].trimmingCharacters(in: .whitespaces)
        if payload.hasPrefix("PresentationAction<") {
            return "Gen.always(\(action).\(caseInfo.name)(.dismiss))"
        }
        if payload.hasPrefix("Result<"),
           payload.hasSuffix(", any Error>") || payload.hasSuffix(", Error>") {
            return "Gen.always(\(action).\(caseInfo.name)(.failure(CancellationError())))"
        }
        return nil
    }

    /// Slice 3/4 (+ coverage widening) — the canned deterministic literal for a
    /// resolved value type (an `IdentifiedArray` element id, slice 3; or a
    /// `BindingAction` field value, slice 4), or `nil` when the type isn't
    /// cheaply defaultable. `UUID` → the all-zero literal (analogous to slice
    /// 2's `CancellationError()` — a fixed constructible value not in the shared
    /// table); everything else delegates to `ViewModelDefaultValue` — the same
    /// defaultable-type table the MVVM protocol faker uses — so both composition
    /// slices cover the same broad surface: **Optionals → `nil`, collections →
    /// `[]` / `[:]`, sized integers / `Float` / `CGFloat` → `0`, `Bool` →
    /// `false`, `String` → `""`**. A custom/concrete type returns `nil` (gates).
    /// This single function is the resolvers' defaultability gate *and* the
    /// emitter's literal source, so the two can't drift.
    static func defaultValueLiteral(for type: String) -> String? {
        let trimmed = type.trimmingCharacters(in: .whitespaces)
        if trimmed == "UUID" {
            return "UUID(uuidString: \"00000000-0000-0000-0000-000000000000\")!"
        }
        return ViewModelDefaultValue.value(for: trimmed)
    }

    /// Names of the excluded (non-constructible) cases, in source order —
    /// the partial-exploration disclosure (guardrail #1, cycle 124).
    static func excludedCaseNames(_ candidate: ReducerCandidate) -> [String] {
        let constructible = Set(constructibleCases(candidate).map(\.name))
        return candidate.actionCases.map(\.name).filter { !constructible.contains($0) }
    }

    /// The raw scalar generator expression for a single-raw-payload case
    /// (delegated to `DerivationStrategist`'s `RawType`, PRD §11), or nil
    /// when the case isn't a single recognized-raw-payload case.
    private static func rawGenerator(for caseInfo: ActionCaseInfo) -> String? {
        guard caseInfo.payloadTypes.count == 1,
              let raw = RawType(typeName: caseInfo.payloadTypes[0]) else { return nil }
        return raw.generatorExpression
    }

    /// The `let actionGen = …` lines for a `.tca` reducer (8-space base indent):
    /// `Gen.always(.free)` per payload-free case, `<rawGen>.map(Action.case)` per
    /// raw-payload case, `<compositionGen>` per recognized wrapper, combined with
    /// `Gen.oneOf(...)` (or used directly when there's exactly one). Internal so
    /// the main file's `makeGeneratorBlock` can call it.
    static func tcaActionGenLines(_ candidate: ReducerCandidate) -> [String] {
        let action = candidate.actionTypeName
        let gens = constructibleCases(candidate).map { caseInfo -> String in
            if let raw = rawGenerator(for: caseInfo) {
                return "\(raw).map(\(action).\(caseInfo.name))"
            }
            if let composition = compositionGenerator(for: caseInfo, action: action) {
                return composition
            }
            return "Gen.always(\(action).\(caseInfo.name))"
        }
        if gens.count == 1 { return ["        let actionGen = \(gens[0])"] }
        var lines = ["        let actionGen = Gen.oneOf("]
        for (index, gen) in gens.enumerated() {
            lines.append("            \(gen)" + (index == gens.count - 1 ? "" : ","))
        }
        lines.append("        )")
        return lines
    }
}
