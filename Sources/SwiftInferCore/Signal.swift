/// One contributing signal collected by a template against a candidate.
///
/// Signals are independent per PRD v0.3 §4.1 — a suggestion can earn or
/// lose confidence from naming alone, types alone, or any combination.
/// The `weight` is signed; vetoes use `Signal.vetoWeight` rather than a
/// large negative number, and `Score` collapses any vetoed signal to the
/// `.suppressed` tier regardless of total.
public struct Signal: Sendable, Equatable {

    /// Catalogue of every signal kind the §4 engine recognises. Kept open
    /// for the M1 templates without preemptively modelling every unused
    /// category — additions cost one case + a row in the PRD weight table.
    public enum Kind: String, Sendable, Equatable, CaseIterable {

        // Positive
        case exactNameMatch
        case typeSymmetrySignature
        case orderedCodomainSignature
        case algebraicStructureCluster
        case reduceFoldUsage
        case discoverableAnnotation
        case testBodyPattern
        case crossValidation
        case samplingPass
        case selfComposition

        // Negative (non-veto)
        case sideEffectPenalty
        case generatorQualityPenalty
        case asymmetricAssertion
        case antiCommutativityNaming
        case partialFunction
        /// V1.4.3 — fires on candidates whose parameter type is a curated
        /// IEEE 754 floating-point-storage type (Float / Double / Float16 /
        /// Float32 / Float64 / Float80 / CGFloat / Complex / Decimal). Emitted
        /// by associativity / commutativity / inverse-pair templates with
        /// weight `-10` (PRD §17.3 step-2 magnitude). Drops Score 30 →
        /// Score 20 (Possible-tier floor) so the suggestion stays surfaced
        /// under `--include-possible` and the explainability block can point
        /// users at PropertyLawKit's `checkFloatingPointPropertyLaws` (kit-
        /// supported types) or document the cycle-2-deferred approximate-
        /// equality template arm (non-kit-supported types). Identity-element
        /// is intentionally exempt — exact identity on FP is reliably true
        /// (`x + 0.0 == x` modulo NaN).
        case floatingPointStorage
        /// V1.4.3b — fires on `RoundTripTemplate` pairs whose forward and
        /// reverse functions have **different** `containingTypeName` values
        /// (excluding the both-nil free-function case, which is a valid
        /// module-scope round-trip). Emitted with weight `-25` — drops
        /// Score 30 → Score 5 (well into Suppressed) so cross-type pairs
        /// are filtered from both default-tier and `--include-possible`
        /// output. Calibration record preserved (the suggestion still
        /// scores; it just lands in Suppressed and gets filtered) so
        /// future cycles can introspect "how many cross-type pairs
        /// did this rule reject."
        ///
        /// Empirical motivation (V1.4.2 cycle-1 baseline): swift-algorithms
        /// surfaced 673 round-trip Possible-tier hits, the vast majority
        /// signature-only matches across distinct `Index` member types
        /// (`AdjacentPairsCollection.Index` / `Chain2Sequence.Index` etc.).
        /// SemanticIndex would catch this via type resolution; this rule
        /// is a cheap pre-SemanticIndex approximation using the textual
        /// `containingTypeName` field already on `FunctionSummary`.
        case crossTypeRoundTripPair
        /// V1.10.1 — fires on `IdempotenceTemplate` candidates whose first
        /// parameter argument label is in a curated direction-label set
        /// (`{after, before, next, prev, previous, advance, succ, pred,
        /// successor, predecessor}`). Emitted with weight `-15` — drops
        /// Score 30 → Score 15 (Suppressed tier, < 20) so Collection-
        /// protocol-style `(T) -> T` increment / decrement ops are filtered
        /// from `--include-possible` output. Curated-verb matches override
        /// (`normalize` etc. produce +40, net +55 → Likely tier preserved).
        ///
        /// **Cycle-6 motivation.** The cycle-6 single-runner triage (50
        /// decisions on the 349-surface) showed idempotence acceptance at
        /// 0/10 = 0%; all 10 rejected idempotence claims were directional
        /// `(T) -> T` ops. Per-decision rationale in
        /// `docs/calibration-cycle-6-data/triage-notes.md`. The counter-
        /// signal closes the dominant 5-of-10 sub-pattern (direction-
        /// labeled args); the remaining 3-of-10 domain-mismatch sub-pattern
        /// (HashTable scale-vs-capacity) is a cycle-8 concern.
        case directionLabel
        /// V1.18.A — fires when the candidate's containing-type carrier
        /// resolves via `CarrierKindResolver` to `.referenceType` (i.e.
        /// `TypeDecl.kind == .class || .actor`). Emitted with weight `-10`
        /// — drops Score 30 → 20 (Possible-tier floor) so reference-type
        /// candidates still earn `--include-possible` surface but are
        /// demoted out of the Likely tier. Algebraic and round-trip
        /// properties are *aliasing-sensitive* on reference types: shared
        /// state through stored references means `var copy = x; copy.op();
        /// x == before(x)` doesn't hold the way it does on value types.
        ///
        /// **Cycle-15 motivation.** Carried forward four cycles
        /// (post-v1.13 priority #5 → post-v1.16 #3 → cycle-14 priority #3)
        /// as a small-projected-effect precision tweak. The v1.18 plan
        /// reframes this as the *necessary structural precondition* for
        /// the workstream-B mutating-method lift (v1.19). See
        /// `docs/v1.18 Calibration Plan.md` workstream A.
        case referenceTypeCarrier
        /// V1.18.A — fires when the candidate's containing-type carrier
        /// resolves via `CarrierKindResolver` to `.valueSemantic`
        /// (`kind == .struct || .enum` AND every stored member is
        /// recursively value-typed per the curated allow-list +
        /// same-corpus `TypeDecl` lookup, depth-bounded 3 levels). Emitted
        /// with weight `+5` — small positive bump that confirms the
        /// algebraic property's structural soundness. Magnitude is
        /// intentionally smaller than `referenceTypeCarrier`'s `-10`
        /// because false positives on reference types are sharper bugs
        /// than missed value-semantic positives.
        ///
        /// Mixed carriers (struct with a class-typed or closure-typed
        /// stored property) emit no signal — conservative; the worked
        /// examples in `docs/ideas/ValueSemantic Kit Proposal.md` §2.2
        /// (broken CoW / closure-captured state) are bugs that look
        /// value-semantic structurally and would falsely score positive
        /// otherwise.
        case valueSemanticCarrier
        /// V1.19.B — fires on suggestions emitted against a
        /// `LiftedTransformation` (a mutating method exposed in its
        /// pure-shadow `(T) -> T` form). Emitted with weight `+10`
        /// per the v1.19 plan open decision #5 lean — modest positive
        /// rewarding the structural soundness check that admitting the
        /// lift requires (strict admission gate filters most noise).
        ///
        /// **Decoupled from `valueSemanticCarrier`.** The `+5`
        /// `valueSemanticCarrier` signal also fires (always — it's the
        /// admission gate); the two contribute independently. A lifted
        /// suggestion's score baseline is therefore the non-lifted
        /// template's baseline + 5 (carrier) + 10 (lift admission), so
        /// the canonical Strong-tier baseline `30 + 40 + 5 + 10 = 85`
        /// for the new `CompositionTemplate` matches the v1.18-plan
        /// suggestion-rendering specification.
        case liftedFromMutation

        // Veto (collapses score to suppressed)
        case nonDeterministicBody
        case nonEquatableOutput
        /// V1.5.1 — fires when the candidate's primary type already
        /// conforms to a protocol whose published laws cover the
        /// `KnownProperty` the template would emit (looked up via
        /// `ProtocolCoverageMap.covers(_:_:)`). The kit's
        /// `check<Protocol>PropertyLaws` is authoritative when a textual
        /// conformance match exists, so the suggestion is genuinely
        /// redundant — full veto rather than a heavy counter-signal.
        /// Calibration record preserved (the suggestion still scores;
        /// it just lands in Suppressed and gets filtered) so cycle-3
        /// metrics can introspect "how many suggestions did
        /// `: AdditiveArithmetic` suppress?". Detail names the matching
        /// conformance + the kit check, e.g. `"Property already covered
        /// by conformance to 'AdditiveArithmetic' — checked by
        /// PropertyLawKit's checkAdditiveArithmeticPropertyLaws"`.
        case protocolCoveredProperty
    }

    /// Sentinel weight that marks a veto. Score arithmetic never sums this
    /// — `Score` checks `isVeto` per signal and short-circuits.
    public static let vetoWeight = Int.min

    public let kind: Kind
    public let weight: Int
    public let detail: String

    public init(kind: Kind, weight: Int, detail: String) {
        self.kind = kind
        self.weight = weight
        self.detail = detail
    }

    /// `true` if this signal vetoes the entire suggestion (PRD §4.4).
    public var isVeto: Bool {
        weight == Self.vetoWeight
    }

    /// Bullet text the explainability block (PRD §4.5) renders for this
    /// signal. Vetoes render as `"<detail> (veto)"`; non-vetoed signals
    /// render `"<detail> (<sign><weight>)"` with `+`/`-` prefixed to the
    /// weight. Templates compose this into their `whySuggested` lines at
    /// suggest time so the renderer just lays out bullets.
    ///
    /// M4.4 consolidated five copies of this formatter (one per
    /// shipped template) into a single value-type extension per the M4
    /// plan's open decision #4 default `(b)` — keeps `whySuggested:
    /// [String]` shape unchanged while eliminating drift risk between
    /// templates.
    public var formattedLine: String {
        if isVeto {
            return "\(detail) (veto)"
        }
        let sign = weight >= 0 ? "+" : ""
        return "\(detail) (\(sign)\(weight))"
    }
}
