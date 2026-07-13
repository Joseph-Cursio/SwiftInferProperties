/// Identity-element candidate emitted by `FunctionScanner` alongside
/// `FunctionSummary`. Captures static value declarations whose name matches
/// the curated identity-shaped list (`zero`, `empty`, `identity`, `none`,
/// `default`) per PRD §5.2's identity-element priority-1 signal.
///
/// `IdentityCandidate` is intentionally textual: `typeText` is the trimmed
/// source representation of the explicit type annotation, mirroring how
/// `Parameter.typeText` and `FunctionSummary.returnTypeText` are stored.
/// M2.5 requires an explicit annotation so the scanner can pair the
/// identity with binary ops whose parameter type matches; type-inferred
/// declarations (e.g. `static let empty = Set<Int>()`) are deferred to
/// M2's open-decision review of the constraint-engine timing.
public struct IdentityCandidate: Sendable, Equatable {

    /// Identifier exactly as written (e.g. `"empty"`, `"zero"`).
    public let name: String

    /// Trimmed source representation of the explicit type annotation
    /// (e.g. `"IntSet"`, `"[String: Int]"`, `"Set<Element>"`).
    public let typeText: String

    /// Innermost containing type-name (e.g. `"IntSet"` for
    /// `extension IntSet { static let empty: IntSet = .init() }`),
    /// or `nil` for top-level static decls.
    public let containingTypeName: String?

    /// File-relative source location of the `let` / `var` keyword.
    public let location: SourceLocation

    public init(
        name: String,
        typeText: String,
        containingTypeName: String?,
        location: SourceLocation
    ) {
        self.name = name
        self.typeText = typeText
        self.containingTypeName = containingTypeName
        self.location = location
    }
}

/// Output of a single scanner pass over a source unit. Bundles the
/// `FunctionSummary` records that drive idempotence / round-trip /
/// commutativity / associativity templates with the `IdentityCandidate`
/// records that drive the M2.5 identity-element template and the
/// `TypeDecl` records that drive M3.3's `EquatableResolver` — all three
/// come from the same AST walk so the §13 perf budget isn't doubled by a
/// second pass.
public struct ScannedCorpus: Sendable, Equatable {

    public let summaries: [FunctionSummary]
    public let identities: [IdentityCandidate]
    public let typeDecls: [TypeDecl]

    /// Functions the scan found but set aside as uncallable from an external test. Never part of
    /// `summaries`, so discovery is unaffected — but a seed naming one can rescue it, with the
    /// access caveat attached.
    public let restricted: [RestrictedFunction]

    public init(
        summaries: [FunctionSummary],
        identities: [IdentityCandidate],
        typeDecls: [TypeDecl],
        restricted: [RestrictedFunction] = []
    ) {
        self.summaries = summaries
        self.identities = identities
        self.typeDecls = typeDecls
        self.restricted = restricted
    }

    public static let empty = Self(summaries: [], identities: [], typeDecls: [])
}
