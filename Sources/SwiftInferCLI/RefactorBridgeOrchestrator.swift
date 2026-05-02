import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// One RefactorBridge proposal — a structural-conformance suggestion the
/// `[A/B/s/n/?]` interactive prompt surfaces alongside per-suggestion
/// Option A. PRD v0.4 §6 + M7.5 plan row.
///
/// Built by `RefactorBridgeOrchestrator.proposals(from:)` from a list of
/// surviving suggestions. One proposal per type (per M7 plan open
/// decision #7 default `(a)` — per-type aggregation). The proposal's
/// `protocolName` is the strongest claim the orchestrator can support
/// from available evidence: `Monoid` if the type has both associativity
/// and identity-element signals; `Semigroup` if only associativity.
public struct RefactorBridgeProposal: Sendable, Equatable {

    /// Type the conformance is proposed for. The text the user wrote in
    /// source — `"Money"`, `"Tally"`, etc. Extension writeout uses this
    /// verbatim as the extended type's name.
    public let typeName: String

    /// Protocol the conformance is proposed against. M7.5 ships
    /// `"Semigroup"` and `"Monoid"`; M8 layers `"CommutativeMonoid"` /
    /// `"Group"` / `"Semilattice"` / `"Ring"` on top via the same
    /// orchestrator surface.
    public let protocolName: String

    /// §4.5 explainability block — "why suggested" + "why this might be
    /// wrong" — assembled from the contributing suggestions' explainability
    /// data plus the per-protocol caveats. Carried through to the
    /// `LiftedConformanceEmitter` so the writeout's comment header
    /// matches what the CLI rendered.
    public let explainability: ExplainabilityBlock

    /// Identity hashes of the suggestions that contributed signals to
    /// this proposal. The interactive prompt uses this set to decide
    /// whether to surface the `B` arm on a given suggestion: present
    /// only when the suggestion's identity is in the set.
    public let relatedIdentities: Set<SuggestionIdentity>

    public init(
        typeName: String,
        protocolName: String,
        explainability: ExplainabilityBlock,
        relatedIdentities: Set<SuggestionIdentity>
    ) {
        self.typeName = typeName
        self.protocolName = protocolName
        self.explainability = explainability
        self.relatedIdentities = relatedIdentities
    }
}

/// Scans a list of `Suggestion`s and emits per-type RefactorBridge
/// proposals. M7.5 ships two arms:
///
/// - **Associativity-only on type T → Semigroup proposal.** A single
///   `associativity` suggestion whose binary op is `(T, T) -> T` with
///   no identity-element pair on the same `T` produces a Semigroup
///   conformance proposal. Per the M7 plan open decision #6 default
///   `(c)`, Semigroup fires on associativity (the kit-side
///   `Semigroup.combineAssociativity` law) — not commutativity, which
///   is structurally orthogonal and lives on M8's `CommutativeMonoid`.
/// - **Associativity + identity-element on type T → Monoid proposal.**
///   When both signals are present on the same `T`, Monoid wins — the
///   conformance covers Semigroup's law via the kit's `.all` chain
///   (PRD §4.3) so emitting both would double-test associativity.
///   Per open decision #7, the orchestrator returns one proposal per
///   type carrying every contributing suggestion's identity in
///   `relatedIdentities`.
///
/// Other templates (idempotence, round-trip, monotonicity, invariant-
/// preservation, commutativity-only) produce no proposals — they're
/// property-level claims, not type-level structural ones. The M8
/// algebraic-structure-composition cluster will widen this surface to
/// `CommutativeMonoid` (commutativity + Monoid signals), `Group`
/// (Monoid + inverse), and the rest of v0.4 PRD §5.4's table.
public enum RefactorBridgeOrchestrator {

    /// Build the per-type proposal map. Suggestions whose template arm
    /// is irrelevant to structural conformance (idempotence, round-trip,
    /// monotonicity, invariant-preservation) are ignored. Returns a
    /// dictionary keyed by type name so the interactive prompt can
    /// look up `proposalsByType[type]` in O(1) per suggestion.
    public static func proposals(from suggestions: [Suggestion]) -> [String: RefactorBridgeProposal] {
        var byType: [String: TypeAccumulator] = [:]
        for suggestion in suggestions {
            guard let signal = templateSignal(of: suggestion),
                  let type = candidateType(of: suggestion) else {
                continue
            }
            byType[type, default: TypeAccumulator(typeName: type)].record(
                signal: signal,
                from: suggestion
            )
        }
        return byType.compactMapValues(\.proposal)
    }

    /// Per-type accumulator — collects which structural signals fired
    /// on the type and which suggestions contributed. The
    /// `proposal` computed property promotes the accumulator to a
    /// `RefactorBridgeProposal` when the signal set warrants one,
    /// returning `nil` otherwise (e.g. commutativity-only with no
    /// associativity peer — no claim to make under M7.5's arm set).
    private struct TypeAccumulator {
        let typeName: String
        var hasAssociativity: Bool = false
        var hasIdentityElement: Bool = false
        var contributing: [Suggestion] = []
        var identities: Set<SuggestionIdentity> = []

        mutating func record(signal: TemplateSignal, from suggestion: Suggestion) {
            switch signal {
            case .associativity: hasAssociativity = true
            case .identityElement: hasIdentityElement = true
            }
            contributing.append(suggestion)
            identities.insert(suggestion.identity)
        }

        var proposal: RefactorBridgeProposal? {
            guard hasAssociativity else { return nil }
            let protocolName = hasIdentityElement ? "Monoid" : "Semigroup"
            return RefactorBridgeProposal(
                typeName: typeName,
                protocolName: protocolName,
                explainability: aggregatedExplainability(protocolName: protocolName),
                relatedIdentities: identities
            )
        }

        private func aggregatedExplainability(protocolName: String) -> ExplainabilityBlock {
            var why: [String] = ["RefactorBridge claim: \(typeName) → \(protocolName)"]
            for suggestion in contributing {
                why.append("from \(suggestion.templateName): \(suggestion.evidence.first?.displayName ?? "<unknown>")")
            }
            let caveats: [String] = [
                "User-supplied combine witness must satisfy associativity.",
                "SwiftInfer does not run the law — applying the conformance lets "
                    + "`swift package protolawcheck` verify it on every CI run."
            ]
            return ExplainabilityBlock(whySuggested: why, whyMightBeWrong: caveats)
        }
    }

    /// Structural-conformance signals M7.5's orchestrator recognizes. M8
    /// will extend this with `commutativity` (for `CommutativeMonoid`),
    /// `inverse` (for `Group`), and `idempotence` (for `Semilattice`).
    private enum TemplateSignal {
        case associativity
        case identityElement
    }

    private static func templateSignal(of suggestion: Suggestion) -> TemplateSignal? {
        switch suggestion.templateName {
        case "associativity": return .associativity
        case "identity-element": return .identityElement
        default: return nil
        }
    }

    /// Extract the candidate type from a suggestion's first-evidence
    /// signature. For associativity / identity-element the shape is
    /// `(T, T) -> T`, so the first parameter type is `T`. Returns
    /// `nil` if the signature can't be parsed (defensive — every
    /// shipped template emits a parseable signature).
    private static func candidateType(of suggestion: Suggestion) -> String? {
        guard let signature = suggestion.evidence.first?.signature else { return nil }
        return InteractiveTriage.paramType(from: signature)
    }
}
