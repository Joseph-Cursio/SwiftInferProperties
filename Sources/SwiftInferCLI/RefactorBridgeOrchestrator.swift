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
///
/// Witness fields (M7.5.a): the bare names of the user's existing
/// binary op (`combineWitness`) and identity element (`identityWitness`,
/// `nil` for Semigroup-only proposals) extracted from the contributing
/// suggestions' evidence. The `LiftedConformanceEmitter` aliases these
/// into the kit's required `static func combine(_:_:)` /
/// `static var identity` so the emitted `extension TypeName: Protocol {…}`
/// compiles in the user's project without manual editing — the gap the
/// kit-side v1.8.0 ship and the SwiftInferProperties v1.8.0+ dep bump
/// don't close on their own.
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

    /// Bare name of the user's existing binary op (e.g. `"merge"` for
    /// a `merge(_:_:)` static), extracted from the associativity
    /// suggestion's `Evidence.displayName`. The conformance writeout
    /// aliases this into the kit's required
    /// `static func combine(_:_:)` via `Self.\(combineWitness)(lhs, rhs)`.
    /// When the witness is already `"combine"`, no aliasing is emitted
    /// (the user's existing static satisfies the requirement directly,
    /// and self-aliasing would recurse infinitely at runtime).
    public let combineWitness: String

    /// Bare name of the user's existing identity element (e.g.
    /// `"empty"` for a `static let empty`), extracted from the
    /// identity-element suggestion's `Evidence.displayName`. `nil` for
    /// Semigroup-only proposals (no identity-element suggestion
    /// contributed). When the witness is already `"identity"`, no
    /// aliasing is emitted; same self-recursion concern as
    /// `combineWitness`.
    public let identityWitness: String?

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
        combineWitness: String,
        identityWitness: String?,
        explainability: ExplainabilityBlock,
        relatedIdentities: Set<SuggestionIdentity>
    ) {
        self.typeName = typeName
        self.protocolName = protocolName
        self.combineWitness = combineWitness
        self.identityWitness = identityWitness
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
    ///
    /// Tracks the witness names per-arm: the associativity arm
    /// contributes `combineWitness` (function name from evidence[0]),
    /// the identity-element arm contributes `identityWitness` (constant
    /// name from evidence[1] — see `IdentityElementTemplate`'s
    /// `makeEvidence(identity:)` for the two-row evidence shape).
    private struct TypeAccumulator {
        let typeName: String
        var hasAssociativity: Bool = false
        var hasIdentityElement: Bool = false
        var combineWitness: String?
        var identityWitness: String?
        var contributing: [Suggestion] = []
        var identities: Set<SuggestionIdentity> = []

        mutating func record(signal: TemplateSignal, from suggestion: Suggestion) {
            switch signal {
            case .associativity:
                hasAssociativity = true
                if combineWitness == nil {
                    combineWitness = combineWitnessName(from: suggestion)
                }
            case .identityElement:
                hasIdentityElement = true
                if combineWitness == nil {
                    combineWitness = combineWitnessName(from: suggestion)
                }
                if identityWitness == nil {
                    identityWitness = identityWitnessName(from: suggestion)
                }
            }
            contributing.append(suggestion)
            identities.insert(suggestion.identity)
        }

        var proposal: RefactorBridgeProposal? {
            guard hasAssociativity, let combineWitness else { return nil }
            let protocolName = hasIdentityElement ? "Monoid" : "Semigroup"
            return RefactorBridgeProposal(
                typeName: typeName,
                protocolName: protocolName,
                combineWitness: combineWitness,
                identityWitness: hasIdentityElement ? identityWitness : nil,
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

    // MARK: - Witness extraction

    /// Strip the parameter-list suffix from a function-evidence
    /// displayName. `"merge(_:_:)"` → `"merge"`. Returns the original
    /// string if no `(` is present (defensive — every shipped template
    /// renders displayName as `<name>(<labels>)`).
    private static func combineWitnessName(from suggestion: Suggestion) -> String? {
        guard let displayName = suggestion.evidence.first?.displayName else { return nil }
        return bareName(from: displayName)
    }

    /// Pull the identity-element name from an `identity-element`
    /// suggestion. `IdentityElementTemplate.makeEvidence(identity:)`
    /// produces displayName `"Tally.empty"` (qualified) or `"empty"`
    /// (top-level); strip the optional type prefix and return the
    /// member name, which the emitter aliases via `Self.<name>`.
    private static func identityWitnessName(from suggestion: Suggestion) -> String? {
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
