import Foundation
import SwiftInferCore
import SwiftInferTemplates

// swiftlint:disable file_length
// M8.4.a widened TemplateSignal from 2 to 4 cases + added Group's
// inverse-element witness threading + per-protocol caveat rendering,
// pushing this file past the 400-line cap. Splitting further would
// scatter the orchestrator's tightly-coupled accumulator + promotion
// logic across two files for minimal reader benefit.

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

    /// Bare name of the user's existing unary inverse function (e.g.
    /// `"negate"` for a `static func negate(_:)`), extracted from
    /// `InverseElementPairing`'s output (M8.3). `nil` for proposals
    /// that don't carry the Group claim — Semigroup, Monoid,
    /// CommutativeMonoid, Semilattice all leave this `nil`. When the
    /// witness is already `"inverse"`, no aliasing is emitted (same
    /// self-recursion concern as `combineWitness` / `identityWitness`).
    /// Added in M8.4.a alongside the kit-side `Group` protocol arm.
    public let inverseWitness: String?

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
        inverseWitness: String? = nil,
        explainability: ExplainabilityBlock,
        relatedIdentities: Set<SuggestionIdentity>
    ) {
        self.typeName = typeName
        self.protocolName = protocolName
        self.combineWitness = combineWitness
        self.identityWitness = identityWitness
        self.inverseWitness = inverseWitness
        self.explainability = explainability
        self.relatedIdentities = relatedIdentities
    }
}

/// Scans a list of `Suggestion`s + `InverseElementPair`s and emits
/// per-type RefactorBridge proposals. The promotion table widens at
/// each milestone — M7.5 shipped Semigroup + Monoid; M8.4.a adds
/// CommutativeMonoid + Group + Semilattice; M8.4.b will add Ring +
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
///
/// **M8.4.a scope deviation from M8 plan open decision #6 (a).** The
/// open-decision default emits separate proposals for incomparable arms
/// (CommutativeMonoid AND Group both apply on the same type → 2 prompts).
/// M8.4.a ships **single-proposal-per-type** semantics — when both apply,
/// Group wins (more requirements; rarer signal). The §4.5 explainability
/// block on the Group proposal mentions the type also satisfies
/// CommutativeMonoid as a forward-pointer. M8.4.b will lift this to
/// multi-proposal with the `[A/B/B'/s/n/?]` prompt extension that open
/// decision #3 promised for the Semilattice + SetAlgebra dual case.
///
/// **Ring detection deferred to M8.4.b.** Ring requires two distinct
/// binary ops on the same type with coordinated additive/multiplicative
/// naming — a per-(type, op-set) accumulator restructure outside M8.4.a
/// scope. PRD §5.4's `Numeric`/stdlib target stays the canonical Ring
/// promotion path; M8.4.a doesn't touch it.
///
/// Other templates (idempotence, round-trip, monotonicity, invariant-
/// preservation, inverse-pair, commutativity-only without associativity)
/// produce no proposals — they're property-level claims, not type-level
/// structural ones.
public enum RefactorBridgeOrchestrator {

    /// Build the per-type proposal map. Suggestions whose template arm
    /// is irrelevant to structural conformance are ignored. Returns a
    /// dictionary keyed by type name so the interactive prompt can
    /// look up `proposalsByType[type]` in O(1) per suggestion.
    ///
    /// `inverseElementPairs` (M8.3 + M8.4.a) carries the unary-inverse
    /// witnesses M8.3's `InverseElementPairing` produced. The
    /// orchestrator records the inverse-element flag + the user's
    /// inverse function name on the type's accumulator so the Group
    /// promotion can fire when associativity + identity are also
    /// present. Defaults to `[]` so M7.5-era callers compile unchanged.
    public static func proposals(
        from suggestions: [Suggestion],
        inverseElementPairs: [InverseElementPair] = []
    ) -> [String: RefactorBridgeProposal] {
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
        // M8.4.a — fold inverse-element witnesses (M8.3) into the same
        // per-type accumulators. Pairs whose op-type doesn't have any
        // suggestion contribution are still recorded — Group can fire
        // even if the associativity / identity-element suggestions
        // came from different files than the inverse function, as long
        // as they all target the same type.
        for pair in inverseElementPairs {
            guard let typeText = pair.operation.returnTypeText else { continue }
            byType[typeText, default: TypeAccumulator(typeName: typeText)]
                .recordInverseElement(witness: pair.inverse.name)
        }
        return byType.compactMapValues(\.proposal)
    }

    /// Per-type accumulator — collects which structural signals fired
    /// on the type and which suggestions contributed. The
    /// `proposal` computed property promotes the accumulator to a
    /// `RefactorBridgeProposal` when the signal set warrants one,
    /// returning `nil` otherwise (e.g. commutativity-only with no
    /// associativity peer — no claim to make).
    ///
    /// Tracks the witness names per-arm: the associativity arm
    /// contributes `combineWitness` (function name from evidence[0]),
    /// the identity-element arm contributes `identityWitness` (constant
    /// name from evidence[1] — see `IdentityElementTemplate`'s
    /// `makeEvidence(identity:)` for the two-row evidence shape), and
    /// M8.3's inverse-element pairing pass contributes `inverseWitness`
    /// (function name from `InverseElementPair.inverse.name`).
    private struct TypeAccumulator {
        let typeName: String
        var hasAssociativity: Bool = false
        var hasIdentityElement: Bool = false
        var hasCommutativity: Bool = false
        var hasIdempotence: Bool = false
        var hasInverseElement: Bool = false
        var combineWitness: String?
        var identityWitness: String?
        var inverseWitness: String?
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
            case .commutativity:
                hasCommutativity = true
                if combineWitness == nil {
                    combineWitness = combineWitnessName(from: suggestion)
                }
            case .idempotence:
                // Idempotence on a binary op `(T, T) -> T` is the
                // Semilattice idempotence law `combine(a, a) == a`.
                // Note: M2's `idempotence` template fires on unary
                // `T -> T` shapes (`f(f(x)) == f(x)`); only binary-op
                // matches contribute here.
                hasIdempotence = true
                if combineWitness == nil {
                    combineWitness = combineWitnessName(from: suggestion)
                }
            }
            contributing.append(suggestion)
            identities.insert(suggestion.identity)
        }

        /// M8.3 inverse-element witness — recorded from
        /// `InverseElementPairing` output, not a Suggestion. Doesn't
        /// add to `relatedIdentities` since no suggestion contributed
        /// (the user doesn't see an "inverse-element" suggestion in
        /// `discover`); the Group prompt threading uses the
        /// associativity / identity-element identities that DO carry.
        mutating func recordInverseElement(witness: String) {
            hasInverseElement = true
            if inverseWitness == nil {
                inverseWitness = witness
            }
        }

        /// Promote to a single `RefactorBridgeProposal` per the M8.4.a
        /// strict-greatest ranking — Semilattice > Group > CommutativeMonoid >
        /// Monoid > Semigroup. Incomparable arms (e.g. CommutativeMonoid AND
        /// Group both apply) collapse to the higher-ranked one with a
        /// forward-pointer in the explainability block; M8.4.b will lift
        /// this to multi-proposal per open decision #6 default `(a)`.
        var proposal: RefactorBridgeProposal? {
            guard hasAssociativity, let combineWitness else { return nil }
            let protocolName = strongestPromotion()
            return RefactorBridgeProposal(
                typeName: typeName,
                protocolName: protocolName,
                combineWitness: combineWitness,
                identityWitness: needsIdentityWitness(for: protocolName) ? identityWitness : nil,
                inverseWitness: protocolName == "Group" ? inverseWitness : nil,
                explainability: aggregatedExplainability(protocolName: protocolName),
                relatedIdentities: identities
            )
        }

        /// Pick the strongest promotion the signal set supports. Order
        /// matters — Semilattice's signal set is a superset of
        /// CommutativeMonoid's (adds idempotence), so the Semilattice
        /// check runs first. Group's signal set is incomparable with
        /// CommutativeMonoid's (inverse vs commutativity); Group ranks
        /// higher for the M8.4.a single-proposal collapse because the
        /// inverse witness is the rarer signal — most everyday Swift
        /// types satisfy CommutativeMonoid (counters, maxes, sets), but
        /// Group requires an explicit unary inverse function.
        private func strongestPromotion() -> String {
            if hasAssociativity, hasIdentityElement, hasCommutativity, hasIdempotence {
                return "Semilattice"
            }
            if hasAssociativity, hasIdentityElement, hasInverseElement {
                return "Group"
            }
            if hasAssociativity, hasIdentityElement, hasCommutativity {
                return "CommutativeMonoid"
            }
            if hasAssociativity, hasIdentityElement {
                return "Monoid"
            }
            return "Semigroup"
        }

        /// Every kit-defined arm except Semigroup needs an identity
        /// witness. M8.4.a's CommutativeMonoid / Group / Semilattice
        /// all extend `Monoid: Semigroup` with `static var identity`.
        private func needsIdentityWitness(for protocolName: String) -> Bool {
            protocolName != "Semigroup"
        }

        private func aggregatedExplainability(protocolName: String) -> ExplainabilityBlock {
            var why: [String] = ["RefactorBridge claim: \(typeName) → \(protocolName)"]
            for suggestion in contributing {
                why.append("from \(suggestion.templateName): \(suggestion.evidence.first?.displayName ?? "<unknown>")")
            }
            if hasInverseElement, let inverseWitness {
                why.append("from inverse-element pairing: \(inverseWitness)(_:) -> \(typeName)")
            }
            // Forward-pointer for the M8.4.a single-proposal collapse:
            // when both CommutativeMonoid and Group apply, Group wins
            // but we surface the alternative claim so the user knows
            // the type has both structures.
            if protocolName == "Group", hasCommutativity {
                why.append(
                    "Note: this type also satisfies CommutativeMonoid "
                        + "(commutativity + identity + associativity). M8.4.b will "
                        + "split incomparable arms into separate proposals; "
                        + "v1.1+ kit-side CommutativeGroup would collapse them."
                )
            }
            let caveats = perProtocolCaveats(for: protocolName)
            return ExplainabilityBlock(whySuggested: why, whyMightBeWrong: caveats)
        }

        private func perProtocolCaveats(for protocolName: String) -> [String] {
            var caveats: [String] = [
                "User-supplied combine witness must satisfy associativity.",
                "SwiftInfer does not run the law — applying the conformance lets "
                    + "`swift package protolawcheck` verify it on every CI run."
            ]
            switch protocolName {
            case "CommutativeMonoid":
                caveats.append(
                    "Commutativity is a Strict law per kit v1.9.0 — "
                    + "`combine(a, b) == combine(b, a)` must hold for every (a, b)."
                )
            case "Group":
                caveats.append(
                    "Inverse witness must satisfy `combine(x, inverse(x)) == .identity` "
                    + "AND `combine(inverse(x), x) == .identity` — both Strict laws "
                    + "per kit v1.9.0."
                )
            case "Semilattice":
                caveats.append(
                    "Idempotence is a Strict law per kit v1.9.0 — "
                    + "`combine(a, a) == a` must hold for every a. Bounded join-semilattices "
                    + "(set union, integer max) and bounded meet-semilattices (set "
                    + "intersection, integer min) share this conformance."
                )
            default:
                break
            }
            return caveats
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

    /// Structural-conformance signals the orchestrator recognizes.
    /// M7.5 shipped associativity + identityElement; M8.4.a adds
    /// commutativity + idempotence (driving CommutativeMonoid /
    /// Semilattice) and inverseElement (driving Group). M8.4.b will
    /// add `ringDistributive` for the two-op Ring detection.
    ///
    /// Note: `inverseElement` doesn't have a corresponding template —
    /// it's a witness record from M8.3's `InverseElementPairing`. The
    /// orchestrator threads it through `recordInverseElement(witness:)`
    /// rather than the suggestion-driven `record(signal:from:)` path.
    /// The case is kept in the enum for documentation symmetry with
    /// the other algebraic signals.
    private enum TemplateSignal {
        case associativity
        case identityElement
        case commutativity
        case idempotence
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
    /// type) and the accumulator's op-shape doesn't change. This is
    /// the v1 design simplification; M8.4.b's per-(type, op) accumulator
    /// will properly disambiguate.
    private static func templateSignal(of suggestion: Suggestion) -> TemplateSignal? {
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
    private static func candidateType(of suggestion: Suggestion) -> String? {
        guard let signature = suggestion.evidence.first?.signature else { return nil }
        return InteractiveTriage.paramType(from: signature)
    }
}
// swiftlint:enable file_length
