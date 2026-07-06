/// A `struct` the engine recognizes as a **value-semantics** verification
/// candidate: it holds reference-backed storage (an escape hatch through which
/// a "value" can leak shared mutable state) and has a mutation surface to
/// exercise. Emitted by `ValueSemanticDiscoverer`.
///
/// Slice 2 of the ValueSemantic build plan (recognition only) surfaces these;
/// later slices verify the kit's copy-mutate-compare law
/// (`checkValueSemanticPropertyLaws`) against each.
///
/// **Why only reference-backed structs.** A pure-value struct (every stored
/// member is a value type) has value semantics for free, so surfacing it would
/// be the Daikon-trap flood the engine avoids. The candidate set is exactly the
/// structs that *can* violate the property — those holding a closure, a known
/// mutable reference container, or a corpus `class`/`actor`.
public struct ValueSemanticCandidate: Sendable, Equatable {

    /// The struct's declared name.
    public let typeName: String

    /// Source location of the struct's `struct` keyword.
    public let location: SourceLocation

    /// The stored members that make the type reference-backed — the escape
    /// hatches a copy-independence bug would leak through. Never empty.
    public let referenceBackedMembers: [ReferenceBackedMember]

    /// Instance methods that could exercise a leak — the mutation surface a
    /// copy-mutate-compare check would drive. Never empty.
    public let mutationSurface: [MutationMethod]

    /// Whether the type is Equatable, per `EquatableResolver`. The kit's
    /// copy-mutate-compare harness compares instances with `==`, so a
    /// non-`.equatable` candidate is surfaced but not verify-ready (a
    /// slice-3 gate). Carried here so recognition stays informative.
    public let equatability: EquatableEvidence

    public init(
        typeName: String,
        location: SourceLocation,
        referenceBackedMembers: [ReferenceBackedMember],
        mutationSurface: [MutationMethod],
        equatability: EquatableEvidence
    ) {
        self.typeName = typeName
        self.location = location
        self.referenceBackedMembers = referenceBackedMembers
        self.mutationSurface = mutationSurface
        self.equatability = equatability
    }
}

/// A stored property that makes its owner reference-backed, tagged with the
/// reason it qualifies (for the "why suggested" explainability output).
public struct ReferenceBackedMember: Sendable, Equatable {

    /// Why a stored member counts as a reference-backed escape hatch.
    public enum Kind: String, Sendable, Equatable {
        /// A function-typed member — a closure can capture shared mutable
        /// state (pbt-book Ch. 9 §9.1.3 / Example 3).
        case closure
        /// A curated Foundation mutable reference container
        /// (`NSMutableArray` / `NSCache` / …) — Example 1.
        case referenceContainer
        /// The member's type resolves to a `class` / `actor` declared in the
        /// scanned corpus — the general reference-container / CoW shape
        /// (Examples 1–2).
        case corpusReference
    }

    public let name: String
    public let typeName: String
    public let kind: Kind

    public init(name: String, typeName: String, kind: Kind) {
        self.name = name
        self.typeName = typeName
        self.kind = kind
    }
}

/// One method in a candidate's mutation surface.
public struct MutationMethod: Sendable, Equatable {

    public let name: String

    /// `true` when declared `mutating` (mutates `self` directly). `false` for
    /// a non-`mutating` instance method retained because it can still leak
    /// through a reference member (the Example-1 shape: a struct method needn't
    /// be `mutating` to mutate a *referenced* object).
    public let isMutating: Bool

    /// Parameter count — a payload-free mutation (0) is directly drivable;
    /// payload-bearing mutations need value generation (a later slice).
    public let parameterCount: Int

    public init(name: String, isMutating: Bool, parameterCount: Int) {
        self.name = name
        self.isMutating = isMutating
        self.parameterCount = parameterCount
    }
}
