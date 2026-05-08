/// V1.5.1 — curated map from textual protocol-conformance names to the
/// set of `KnownProperty` values whose published laws PropertyLawKit's
/// `check<Protocol>PropertyLaws` family already covers. Used by
/// V1.5.2's `protocolCoverageVeto(...)` helper across the five
/// algebraic templates (idempotence / commutativity / associativity /
/// inverse-pair / identity-element / round-trip) to suppress
/// suggestions whose property is genuinely redundant given the
/// candidate type's existing conformances.
///
/// **Why this is a veto, not a counter-signal.** Cycle-1's
/// `crossTypeRoundTripPair` used `-25` (a heavy counter-signal that
/// drops Score 30 → 5 = Suppressed) because the underlying rule was
/// approximate — textual `containingTypeName` matching is a
/// pre-SemanticIndex stand-in for type resolution. Protocol coverage
/// is authoritative when the textual conformance match holds: the
/// kit's `check<Protocol>PropertyLaws` *does* verify the property the
/// template would have emitted. v1.5 plan open-decision #3 default
/// (a) full veto.
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
    /// **13 keys** — the v1.5 plan's enumerated stdlib + kit set:
    /// `Equatable` / `Comparable` / `Hashable` / `AdditiveArithmetic` /
    /// `Numeric` / `SignedNumeric` / `SetAlgebra` / `Codable` plus kit
    /// `Semigroup` / `Monoid` / `CommutativeMonoid` / `Group` /
    /// `Semilattice`. `Encodable` and `Decodable` are deliberately
    /// excluded — neither alone covers `codableRoundTrip` (round-trip
    /// requires both encode and decode), and listing them with empty
    /// sets would add textual-match noise without behavioural benefit.
    public static let protocolCoverage: [String: Set<KnownProperty>] = [
        // — stdlib equality / ordering / hashing —
        "Equatable": equatableBase,
        "Comparable": equatableBase.union([.comparableTotalOrder]),
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
        "SetAlgebra": equatableBase.union([
            .setUnionAssociative,
            .setUnionCommutative,
            .setUnionEmptyIdentity,
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
    /// `protocolCoverageVeto(...)` helper.
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
    /// the per-template `protocolCoverageVeto(...)` helpers share one
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
    public static func coverageVetoSignal(
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

/// Catalogue of property surfaces SwiftInfer's algebraic templates can
/// emit. v1.5 introduces this enum so `ProtocolCoverageMap` has a
/// closed vocabulary to map conformances against; future template arms
/// add cases here as they ship (e.g. cycle-2-deferred
/// `KitFloatingPointTemplate` will emit a transcendental-shape property).
///
/// Co-located with `ProtocolCoverageMap` per v1.5 plan open-decision #2
/// default: the enum exists to be looked up against the table;
/// splitting them into separate files adds an import hop without
/// adding clarity. Mirrors `FloatingPointStorageNames`'s self-contained
/// posture.
public enum KnownProperty: String, Sendable, Hashable, CaseIterable {

    // — Additive (stdlib AdditiveArithmetic / Numeric / SignedNumeric)
    /// `(a + b) + c == a + (b + c)`
    case additiveAssociative
    /// `a + b == b + a`
    case additiveCommutative
    /// `a + .zero == a`
    case additiveIdentityZero
    /// `a + (-a) == .zero`
    case additiveInverse

    // — Multiplicative (stdlib Numeric / SignedNumeric) —
    /// `(a * b) * c == a * (b * c)`
    case multiplicativeAssociative
    /// `a * b == b * a`
    case multiplicativeCommutative
    /// `a * 1 == a`
    case multiplicativeIdentityOne
    /// `a * a⁻¹ == 1` (not covered by Numeric — listed for symmetry
    /// with `additiveInverse`; populated by future field-shaped arms.)
    case multiplicativeInverse

    // — Numeric distributivity —
    /// `a * (b + c) == a * b + a * c`
    case distributivity

    // — Set algebra (stdlib SetAlgebra) —
    /// `(a ∪ b) ∪ c == a ∪ (b ∪ c)`
    case setUnionAssociative
    /// `a ∪ b == b ∪ a`
    case setUnionCommutative
    /// `a ∪ ∅ == a`
    case setUnionEmptyIdentity
    /// `a ∩ a == a`
    case setIntersectionIdempotent

    // — Equatable / Comparable / Hashable —
    /// `a == a`
    case equatableReflexive
    /// `a == b ⇒ b == a`
    case equatableSymmetric
    /// `a == b ∧ b == c ⇒ a == c`
    case equatableTransitive
    /// strict-weak-ordering laws on `<` (Swift Comparable)
    case comparableTotalOrder
    /// `a == b ⇒ a.hashValue == b.hashValue`
    case hashableConsistency

    // — Codable —
    /// `decode(encode(x)) == x`
    case codableRoundTrip

    // — Kit-shaped (PropertyLawKit Monoid / Group / Semilattice) —
    /// kit `Monoid`'s identity law on `combine`
    case monoidIdentity
    /// kit `Group`'s inverse law on `combine`
    case groupInverse
    /// kit `Semilattice`'s idempotent-`combine` law (`x ⊕ x == x`)
    case semilatticeIdempotence
}
