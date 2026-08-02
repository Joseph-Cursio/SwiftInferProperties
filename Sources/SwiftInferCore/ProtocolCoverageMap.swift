/// V1.5.1 — curated map from textual protocol-conformance names to the
/// set of `KnownProperty` values whose published laws PropertyLawKit's
/// `check<Protocol>PropertyLaws` family already covers. Used by
/// V1.5.2's `assumedKitCoverage(...)` helper across the five
/// algebraic templates (idempotence / commutativity / associativity /
/// inverse-pair / identity-element / round-trip) to suppress
/// suggestions whose property is genuinely redundant given the
/// candidate type's existing conformances.
///
/// **Why this DEFERS rather than counter-signals — known information removes
/// the need to infer.** Cycle-1's `crossTypeRoundTripPair` used `-25` (a heavy
/// counter-signal that drops Score 30 → 5 = Suppressed) because the underlying
/// rule was approximate — textual `containingTypeName` matching is a
/// pre-SemanticIndex stand-in for type resolution. This is a different kind of
/// thing. A conformance is a *fact about the code*, and where the kit genuinely
/// runs the law there is nothing left to infer: re-reporting another tool's
/// finding teaches people the tools disagree. The suppression is full-strength
/// because it expresses **deference**, not confidence that the suggestion is
/// wrong. v1.5 plan open-decision #3 default (a).
///
/// **This is deliberately NOT called a veto, and the distinction is load-bearing.**
/// The six other `*Veto` helpers in the templates — `predicateVeto`,
/// `setAlgebraShapeVeto`, `producerVeto`, `nonDeterministicVeto`, the
/// math-forward and iterator gates — all mean *this law is FALSE or unsafe
/// here*. This one means *this law is TRUE and someone authoritative already
/// runs it*. Those are opposite claims, and while one word covered both, a
/// suppressed-because-redundant row and a deleted-law-nobody-checks row were
/// indistinguishable in the vocabulary. That is not hypothetical: it is exactly
/// how `setUnionAssociative` survived — see `docs/protocol-coverage-law-drift.md`,
/// and `ProtocolCoverageAudit`'s standing line, *"a veto that prevents
/// double-reporting looks exactly like nothing to report."*
///
/// **But the deference is only as good as the claim, and the claim is hearsay.**
/// Each entry asserts that `check<Protocol>PropertyLaws` runs a specific law, in
/// a package this one pins by version and whose source nothing here reads. Only
/// `SetAlgebra` has been checked law-by-law (2026-08-02, kit v3.21.0); at that
/// point **13 of 56 `(key, law)` pairs were false**. The other sixteen keys are
/// still asserting on trust, and `KitCoverageDriftTests` guards the KEY — does
/// the kit ship a suite by this name — never the VALUE. The name says `assumed`
/// because that is the honest epistemic status, matching
/// `ProtocolCoverageAudit`'s own `verified` / `assumed` / `contradicted` split.
///
/// **Hand-baked transitive coverage.** Each entry's `Set<KnownProperty>`
/// already includes its parents'. `Numeric`'s set contains everything
/// `AdditiveArithmetic`'s contains, plus the multiplicative properties.
/// `SignedNumeric` contains `Numeric`'s plus `additiveInverse`. Computing
/// transitivity at lookup time would require modelling Swift's protocol
/// inheritance graph — a v1.1 constraint-engine concern (PRD §20.2) —
/// so v1.5 takes the ~14 × 5 = ~70 lookup-table-entry cost in exchange
/// for zero textual-conformance-walk logic.
///
/// **Textual-only matching, v1 limitation.** Like
/// `EquatableResolver.knownEquatableConformance`, this is a string
/// keyset. `: Swift.Numeric` written out fully won't match the bare
/// `"Numeric"` key (cycle-3 may add a normalization step that strips
/// known module prefixes; documented in v1.5 plan §"Out of scope").
/// Conditional conformance (`Array<T>: Equatable where T: Equatable`)
/// is not modelled either — a v1.1 constraint-engine concern.
/// User-defined protocols inheriting from a curated key
/// (`MyAlgebra: Numeric`) won't get coverage unless the conforming
/// type *also* textually lists `Numeric`.
///
/// **Empty sets are intentional placeholders.** `Semigroup` carries
/// `[]` because v1.5's algebraic templates don't emit a property the
/// kit's `checkSemigroupPropertyLaws` covers — there is no
/// `combineAssociative` template. Keeping the key present documents
/// that the protocol was considered; future cycles can populate it
/// without a schema change.
public enum ProtocolCoverageMap {

    /// Property-coverage table keyed by textual protocol-conformance
    /// name. Values include parent-protocol properties (transitive
    /// coverage hand-baked).
    ///
    /// **17 keys.** The v1.5 plan enumerated 13 — `Equatable` / `Comparable` /
    /// `Hashable` / `AdditiveArithmetic` / `Numeric` / `SignedNumeric` /
    /// `SetAlgebra` / `Codable` plus kit `Semigroup` / `Monoid` /
    /// `CommutativeMonoid` / `Group` / `Semilattice` — and `Strideable`,
    /// `IteratorProtocol`, `Sequence`, `LosslessStringConvertible` were added
    /// 2026-07-30 / 2026-08-01 without updating this count. Corrected 2026-08-02.
    ///
    /// **Only `SetAlgebra` has been verified law-by-law against the kit.** The
    /// other 16 keys assert the same kind of claim and nothing checks them;
    /// `KitCoverageDriftTests` guards the KEY (does the kit ship a suite by this
    /// name) and never the VALUE. Measured 2026-08-02: 13 of 56 `(key, law)`
    /// claims were false, 12 of them the `equatableBase` union below — see
    /// `docs/protocol-coverage-law-drift.md` §4.
    ///
    /// `Encodable` and `Decodable` are deliberately
    /// excluded — neither alone covers `codableRoundTrip` (round-trip
    /// requires both encode and decode), and listing them with empty
    /// sets would add textual-match noise without behavioural benefit.
    public static let protocolCoverage: [String: Set<KnownProperty>] = [
        // — stdlib equality / ordering / hashing —
        "Equatable": equatableBase,
        "Comparable": equatableBase.union([.comparableTotalOrder]),
        "Strideable": [.strideableDistanceRoundTrip],
        // Sequence inherits the IteratorProtocol suite (`SequenceLaws.swift:91`), so a
        // carrier reached as either name is covered.
        "IteratorProtocol": [.iteratorTerminationStability],
        "Sequence": [.iteratorTerminationStability],
        "LosslessStringConvertible": [.losslessStringRoundTrip],
        "Hashable": equatableBase.union([.hashableConsistency]),

        // — stdlib arithmetic chain —
        // AdditiveArithmetic: Equatable
        "AdditiveArithmetic": additiveArithmeticBase,
        // Numeric: AdditiveArithmetic, ExpressibleByIntegerLiteral
        "Numeric": numericBase,
        // SignedNumeric: Numeric
        "SignedNumeric": numericBase.union([.additiveInverse]),

        // — stdlib set algebra —
        // SetAlgebra: Equatable, ExpressibleByArrayLiteral
        //
        // Verified law-by-law against `SetAlgebraLaws.swift` on 2026-08-02 (kit `4a2dada`,
        // fifteen laws). Two corrections landed from that sweep — see
        // `docs/protocol-coverage-law-drift.md`:
        //
        //   1. `setUnionAssociative` was here and the kit ships NO associativity law for
        //      sets, of any operand. `grep -rn "unionAssociat"` in SwiftPropertyLaws: zero
        //      hits. The identifier is gone entirely rather than merely unmapped — its only
        //      meaning was a false claim, and leaving it invites re-adding it here.
        //   2. `intersectionCommutativity`, `symmetricDifferenceCommutativity` and
        //      `unionIdempotence` ARE run by the kit and were unclaimed, so `discover`
        //      double-reported all three (the `Strideable` defect, three more times).
        //
        // Still unclaimed, deliberately: the `symmetricDifference` self/empty/definition
        // three, distributivity ×2, absorption ×2, De Morgan ×2, and `emptyIdentity`'s
        // intersection twin. No template proposes any of them, so claiming coverage would
        // assert something nothing exercises. Add the entry WITH the template, not before.
        "SetAlgebra": equatableBase.union([
            .setUnionCommutative,
            .setIntersectionCommutative,
            .setSymmetricDifferenceCommutative,
            .setUnionEmptyIdentity,
            .setUnionIdempotent,
            .setIntersectionIdempotent
        ]),

        // — stdlib codable —
        "Codable": [.codableRoundTrip],

        // — kit algebraic protocols (PropertyLawKit ≥ 2.0.0) —
        // Semigroup: a binary `combine` op that's associative — but
        // SwiftInfer's templates don't emit a `combineAssociative`
        // property today, so the curated set is empty. Placeholder
        // documents that the protocol was considered.
        "Semigroup": [],
        // Monoid: Semigroup + identity element
        "Monoid": monoidBase,
        // CommutativeMonoid: Monoid + commutativity. The commutativity
        // applies to the kit `combine` op, which our templates don't
        // emit a property for — so behaviourally this matches Monoid's
        // coverage (identity only). Listed separately to document
        // consideration; cycle-3 may extend if a `combineCommutative`
        // template arm ships.
        "CommutativeMonoid": monoidBase,
        // Group: Monoid + inverse
        "Group": monoidBase.union([.groupInverse]),
        // Semilattice: Monoid + idempotent commutative `combine`. Maps
        // to `semilatticeIdempotence` (the kit-shaped property the
        // idempotence template emits when the type's `combine`-shaped
        // op meets the kit's posture).
        "Semilattice": monoidBase.union([.semilatticeIdempotence])
    ]

    // MARK: - Hand-baked parent sets (kept private so the public
    //          `protocolCoverage` table is the single canonical surface)

    private static let equatableBase: Set<KnownProperty> = [
        .equatableReflexive,
        .equatableSymmetric,
        .equatableTransitive
    ]

    private static let additiveArithmeticBase: Set<KnownProperty> = equatableBase.union([
        .additiveAssociative,
        .additiveCommutative,
        .additiveIdentityZero
    ])

    private static let numericBase: Set<KnownProperty> = additiveArithmeticBase.union([
        .multiplicativeAssociative,
        .multiplicativeCommutative,
        .multiplicativeIdentityOne,
        .distributivity
    ])

    private static let monoidBase: Set<KnownProperty> = [.monoidIdentity]

    /// Returns `true` when `protocolName`'s curated coverage set
    /// includes `property`. Bare textual match against the table key —
    /// callers pass the protocol's short name (e.g.
    /// `"AdditiveArithmetic"`, not `"Swift.AdditiveArithmetic"`). See
    /// the type-level docs for the v1 textual-only limitations.
    public static func covers(_ protocolName: String, _ property: KnownProperty) -> Bool {
        protocolCoverage[protocolName]?.contains(property) ?? false
    }

    /// Returns `true` when **any** of `inheritedTypes` (the candidate
    /// type's textual conformance list, already populated by
    /// `TypeShapeBuilder`) covers `property`. Convenience wrapper
    /// around `covers(_:_:)` — the V1.5.2 template helpers will use
    /// this shape to walk the merged conformance list once per
    /// candidate.
    public static func anyCovers<S: Sequence>(
        _ inheritedTypes: S,
        _ property: KnownProperty
    ) -> Bool where S.Element == String {
        inheritedTypes.contains { covers($0, property) }
    }

    /// First conformance in `inheritedTypes` whose curated coverage
    /// set includes `property`, or `nil` if none does. V1.5.2 uses
    /// this to populate the veto's `detail` string with the matching
    /// conformance name (so the explainability bullet can say
    /// `"Property already covered by conformance to 'AdditiveArithmetic'"`).
    /// First-match-wins is fine because the veto fires identically
    /// regardless of which parent supplies the coverage.
    ///
    /// **V1.6.1 patch — citation determinism.** When the caller passes
    /// a `Set<String>` (non-deterministic iteration order across
    /// process invocations), we sort the members lexicographically
    /// before scanning so the cited protocol in the veto's `detail`
    /// string is stable across runs. Sequence callers (Array, etc.)
    /// retain their input order. Cycle-2 finding: suppressed
    /// suggestions don't appear in stdout (so byte-stability of
    /// user-visible output already held), but Decisions records that
    /// introspect veto reasons saw different cited protocols across
    /// runs. Closes that gap.
    public static func firstCoveringProtocol<S: Sequence>(
        in inheritedTypes: S,
        for property: KnownProperty
    ) -> String? where S.Element == String {
        inheritedTypes.sorted().first { covers($0, property) }
    }

    /// V1.5.2 — fold a flat `[TypeDecl]` corpus into a `name → union of
    /// inherited types` index. Mirrors `EquatableResolver`'s posture:
    /// extension records (cross-file included) merge into the same
    /// keyed set as their primary decl. Generic parameters are stripped
    /// from the keys (`Array<T>` extension records under `Array`) so
    /// per-call lookups by stripped `summary.parameters[0].typeText`
    /// hit consistently.
    ///
    /// Built once per `discover()` pass, threaded through
    /// `collectSuggestions(...)` to each algebraic template's
    /// `assumedKitCoverage(...)` helper.
    ///
    /// **V1.7.1 — curated stdlib bake-in.** The result is seeded with
    /// `stdlibConformances` so a `let x: Int` candidate resolves to
    /// `Int`'s known conformances (`AdditiveArithmetic` / `Numeric` /
    /// `Comparable` / `Hashable` / `Codable` / `Equatable` etc.) even
    /// when the corpus doesn't declare any `extension Int: ...`.
    /// Closes cycle-2's headline 0-delta finding on stdlib-typed
    /// carriers across OrderedCollections / Algorithms / PropertyLawKit.
    /// Per-key `formUnion` semantics preserved — a corpus
    /// `extension Int: SomeProto` adds `SomeProto` to `Int`'s curated
    /// set rather than replacing it.
    public static func inheritedTypesIndex(from typeDecls: [TypeDecl]) -> [String: Set<String>] {
        var index: [String: Set<String>] = [:]
        // V1.7.1 — seed with curated stdlib bake-in. Order is stable:
        // every key in `stdlibConformances` lands first, then corpus
        // typeDecls union in. `formUnion` on the seeded set means
        // corpus `extension Int: SomeProto` lifts to
        // `Int → {curated... ∪ SomeProto}`.
        for (typeName, conformances) in stdlibConformances {
            index[typeName] = conformances
        }
        for decl in typeDecls {
            guard !decl.inheritedTypes.isEmpty else { continue }
            let key = strippingGenericParameters(decl.name)
            index[key, default: []].formUnion(decl.inheritedTypes)
        }
        return index
    }

    /// V1.5.2 — strip a single generic-parameter list from a textual
    /// type name. Mirrors `FloatingPointStorageNames`'s same-named
    /// helper. Hosting it here lets `inheritedTypesIndex(from:)` and
    /// the per-template `assumedKitCoverage(...)` helpers share one
    /// stripping rule without a cross-module dependency.
    public static func strippingGenericParameters(_ name: String) -> String {
        guard let openAngle = name.firstIndex(of: "<") else { return name }
        return String(name[..<openAngle])
    }

    /// V1.5.2 — first-match-wins veto Signal across a candidate
    /// `KnownProperty` set. Each algebraic template builds its
    /// candidate set from its emission shape (idempotence: set +
    /// semilattice; commutativity: op-class-mapped; etc.) and calls
    /// this factory. Returns `nil` when none of `candidateProperties`
    /// is covered by any conformance in `inheritedTypesByName[typeName]`.
    /// The matched conformance name is interpolated into the
    /// explainability detail line so the user can audit which kit law
    /// is doing the covering.
    public static func assumedCoverageSignal(
        forTypeText typeText: String?,
        inheritedTypesByName: [String: Set<String>],
        candidateProperties: [KnownProperty]
    ) -> Signal? {
        guard let typeText else { return nil }
        let key = strippingGenericParameters(typeText)
        guard let inherited = inheritedTypesByName[key] else { return nil }
        for property in candidateProperties {
            if let covering = firstCoveringProtocol(in: inherited, for: property) {
                return Signal(
                    kind: .protocolCoveredProperty,
                    weight: Signal.vetoWeight,
                    detail: "Property already covered by conformance to "
                        + "'\(covering)' — checked by PropertyLawKit's "
                        + "check\(covering)PropertyLaws"
                )
            }
        }
        return nil
    }
}
