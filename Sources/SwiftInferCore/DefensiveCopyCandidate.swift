/// A `class` the engine recognizes as a **defensive-copy** verification
/// candidate: it declares a `copy()` / `clone()`-style method returning its own
/// type, so it *claims* that copy is equal-by-value, a distinct object, and
/// independent of the source. Emitted by `DefensiveCopyDiscoverer`.
///
/// The reference-type companion to `ValueSemanticCandidate` (pbt-book Ch. 9
/// §9.3). High-precision: only classes with an explicit copy method are
/// candidates, not every class.
public struct DefensiveCopyCandidate: Sendable, Equatable {

    /// The class's declared name.
    public let typeName: String

    /// Source location of the class's `class` keyword.
    public let location: SourceLocation

    /// The copy method under test (a curated copy-verb name returning the class
    /// type) — the verifier calls it as `copyUnderTest()`.
    public let copyMethodName: String

    /// Instance methods that mutate the class — used to drive the copy through
    /// states + to exercise copy-independence. (Reuses `MutationMethod`.)
    public let mutationSurface: [MutationMethod]

    /// Whether the class is Equatable, per `EquatableResolver`. The harness
    /// compares instances with `==`, so a non-`.equatable` candidate is surfaced
    /// but not verify-ready.
    public let equatability: EquatableEvidence

    public init(
        typeName: String,
        location: SourceLocation,
        copyMethodName: String,
        mutationSurface: [MutationMethod],
        equatability: EquatableEvidence
    ) {
        self.typeName = typeName
        self.location = location
        self.copyMethodName = copyMethodName
        self.mutationSurface = mutationSurface
        self.equatability = equatability
    }
}
