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
