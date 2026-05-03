import SwiftInferCore
import SwiftInferTemplates

/// Scans a list of `Suggestion`s + `InverseElementPair`s and emits
/// per-type RefactorBridge proposals. The promotion table widens at
/// each milestone — M7.5 shipped Semigroup + Monoid; M8.4.a added
/// CommutativeMonoid + Group + Semilattice; M8.4.b.2 added Ring +
/// the SetAlgebra secondary arm.
///
/// **Promotion table (PRD v0.4 §5.4).** Strict-greatest within each
/// inheritance chain branch — Semigroup → Monoid → CommutativeMonoid →
/// Semilattice on the commutativity branch; Semigroup → Monoid →
/// Group on the inverse branch. At each level, every contributing
/// suggestion's identity is added to `relatedIdentities` so the
/// interactive prompt's `B` arm surfaces consistently.
///
/// | Signals on type T | Proposal | Witnesses |
/// |---|---|---|
/// | associativity | Semigroup *(M7.5)* | combine |
/// | associativity + identity | Monoid *(M7.5)* | combine, identity |
/// | associativity + identity + commutativity | CommutativeMonoid *(M8.4.a)* | combine, identity |
/// | associativity + identity + inverse-element | Group *(M8.4.a)* | combine, identity, inverse |
/// | associativity + commutativity + idempotence (+ optional identity) | Semilattice *(M8.4.a)* | combine, identity |
/// | per-op: assoc + identity for additive AND multiplicative | Numeric/Ring *(M8.4.b.2)* | additive op + identity |
public enum RefactorBridgeOrchestrator {

    /// Build the per-type proposal map. Suggestions whose template arm
    /// is irrelevant to structural conformance are ignored. Returns a
    /// dictionary keyed by type name so the interactive prompt can
    /// look up `proposalsByType[type]` in O(1) per suggestion.
    ///
    /// **M8.4.b.1**: each type can carry **multiple** proposals — open
    /// decisions #3 + #6. Two cases trigger a list of length > 1:
    /// - **Incomparable arms** (open decision #6): when both
    ///   `CommutativeMonoid` and `Group` fire on the same type, the
    ///   orchestrator emits both as peer proposals.
    /// - **Semilattice + SetAlgebra secondary** (open decision #3):
    ///   a Semilattice claim whose binary op is curated set-named
    ///   (`union` / `intersect` / `subtract` / etc.) emits a
    ///   secondary `SetAlgebra` proposal alongside.
    ///
    /// The list ordering matters for the prompt UI: position 0 is
    /// rendered as `B`, position 1 as `B'` in the `[A/B/B'/s/n/?]`
    /// extended prompt.
    ///
    /// `inverseElementPairs` (M8.3 + M8.4.a) carries the unary-inverse
    /// witnesses. Defaults to `[]` so M7.5-era callers compile.
    public static func proposals(
        from suggestions: [Suggestion],
        inverseElementPairs: [InverseElementPair] = []
    ) -> [String: [RefactorBridgeProposal]] {
        var byType: [String: RefactorBridgeAccumulator] = [:]
        for suggestion in suggestions {
            guard let signal = templateSignal(of: suggestion),
                  let type = candidateType(of: suggestion) else {
                continue
            }
            byType[type, default: RefactorBridgeAccumulator(typeName: type)].record(
                signal: signal,
                from: suggestion
            )
        }
        // M8.4.a — fold inverse-element witnesses (M8.3) into the same
        // per-type accumulators. Pairs whose op-type doesn't have any
        // suggestion contribution are still recorded — Group can fire
        // even if the associativity / identity-element suggestions came
        // from different files than the inverse function, as long as
        // they all target the same type.
        for pair in inverseElementPairs {
            guard let typeText = pair.operation.returnTypeText else { continue }
            byType[typeText, default: RefactorBridgeAccumulator(typeName: typeText)]
                .recordInverseElement(witness: pair.inverse.name)
        }
        return byType.compactMapValues { accumulator in
            let list = accumulator.proposals
            return list.isEmpty ? nil : list
        }
    }

    /// Map a template name to its `TemplateSignal`. Only templates
    /// whose suggestions contribute to a structural conformance return
    /// a signal — round-trip / monotonicity / invariant-preservation /
    /// inverse-pair are property-level claims and produce no proposal.
    ///
    /// Note: M2's `idempotence` template fires on unary `T -> T`
    /// shapes (`f(f(x)) == f(x)` for normalizers, sanitizers, etc.).
    /// Semilattice's idempotence law is on a *binary* op
    /// (`combine(a, a) == a`). The shape mismatch means a unary
    /// idempotence suggestion on type T doesn't surface a Semilattice
    /// claim on T's binary op — `candidateType` extracts T (the param
    /// type) and the accumulator's op-shape doesn't change.
    static func templateSignal(of suggestion: Suggestion) -> TemplateSignal? {
        switch suggestion.templateName {
        case "associativity": return .associativity
        case "identity-element": return .identityElement
        case "commutativity": return .commutativity
        case "idempotence": return .idempotence
        default: return nil
        }
    }

    /// Extract the candidate type from a suggestion's first-evidence
    /// signature. For associativity / identity-element / commutativity
    /// the shape is `(T, T) -> T`; for idempotence it's `T -> T`. In
    /// both cases the first parameter type is `T`. Returns `nil` if
    /// the signature can't be parsed (defensive — every shipped
    /// template emits a parseable signature).
    static func candidateType(of suggestion: Suggestion) -> String? {
        guard let signature = suggestion.evidence.first?.signature else { return nil }
        return InteractiveTriage.paramType(from: signature)
    }
}

/// Pure helpers for pulling witness names out of `Suggestion.evidence`
/// rows. Used by `RefactorBridgeAccumulator.record(signal:from:)`.
enum WitnessExtractor {

    /// Strip the parameter-list suffix from a function-evidence
    /// displayName. `"merge(_:_:)"` → `"merge"`. Returns the original
    /// string if no `(` is present (defensive — every shipped template
    /// renders displayName as `<name>(<labels>)`).
    static func combineWitnessName(from suggestion: Suggestion) -> String? {
        guard let displayName = suggestion.evidence.first?.displayName else { return nil }
        return bareName(from: displayName)
    }

    /// Pull the identity-element name from an `identity-element`
    /// suggestion. `IdentityElementTemplate.makeEvidence(identity:)`
    /// produces displayName `"Tally.empty"` (qualified) or `"empty"`
    /// (top-level); strip the optional type prefix and return the
    /// member name, which the emitter aliases via `Self.<name>`.
    static func identityWitnessName(from suggestion: Suggestion) -> String? {
        guard suggestion.evidence.count >= 2,
              let displayName = suggestion.evidence.dropFirst().first?.displayName else {
            return nil
        }
        if let dotIndex = displayName.lastIndex(of: ".") {
            return String(displayName[displayName.index(after: dotIndex)...])
        }
        return displayName
    }

    /// Strip parens-and-after from a function display name.
    private static func bareName(from displayName: String) -> String {
        guard let parenIndex = displayName.firstIndex(of: "(") else { return displayName }
        return String(displayName[..<parenIndex])
    }
}
