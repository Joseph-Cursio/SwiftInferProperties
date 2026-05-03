import SwiftInferCore

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
