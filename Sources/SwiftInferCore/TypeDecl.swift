import ProtoLawCore

/// Type-declaration record emitted by `FunctionScanner` alongside
/// `FunctionSummary` and `IdentityCandidate`. Captures the source-textual
/// shape of every `struct` / `class` / `enum` / `actor` / `extension` decl
/// the scanner walks, so M3.3's `EquatableResolver` and M4.1's
/// `TypeShapeBuilder` can answer "is this type Equatable?" / "what
/// generator strategy applies to this type?" against a corpus-wide
/// picture without a second pass over the AST.
///
/// Per the M3 plan's open decision #2: extensions emit their own
/// `TypeDecl` carrying just the conformances the extension adds — the
/// resolver merges multiple `TypeDecl`s per type name (mergeable
/// multimap-shaped, one record per source decl). This keeps the data
/// model flat at the cost of asking the consumer to fold by name.
///
/// `TypeDecl` is intentionally textual: `inheritedTypes` and the
/// `StoredMember.typeName` strings are stored as trimmed source
/// representations, mirroring how `Parameter.typeText` and
/// `IdentityCandidate.typeText` are stored. Conditional conformance
/// reasoning (`Array<T>: Equatable where T: Equatable`) is a v1.1
/// constraint-engine concern (PRD §20.2) and out of scope here.
public struct TypeDecl: Sendable, Equatable {

    /// Surface-syntactic kind of the source declaration. Mirrors
    /// `ProtoLawCore.TypeShape.Kind` for `struct` / `class` / `enum` /
    /// `actor`, and adds `.extension` so extension conformances stay
    /// distinguishable from primary declarations during resolver merging.
    public enum Kind: String, Sendable, Equatable {
        case `struct`
        case `class`
        case `enum`
        case `actor`
        case `extension`
    }

    /// For primary decls, the type's identifier as written. For
    /// extensions, the trimmed `extendedType` text (e.g. `"Array"`,
    /// `"Dictionary<String, Int>"`).
    public let name: String

    public let kind: Kind

    /// Inheritance-clause type names verbatim, in source order. For
    /// extensions, only the conformances the extension itself adds.
    /// Empty when the decl has no inheritance clause.
    public let inheritedTypes: [String]

    /// File-relative source location of the declaration's keyword
    /// (`struct` / `class` / `enum` / `actor` / `extension`).
    public let location: SourceLocation

    /// `true` when this decl's body declares a static `gen()` method.
    /// Per the M4 plan's open decision #1 (same-file only),
    /// `TypeShapeBuilder` ORs this across same-file `TypeDecl`s to
    /// surface the `DerivationStrategy.userGen` short-circuit per PRD
    /// §5.7 Strategy A. Defaults to `false` so M3-era call sites that
    /// don't yet populate the field continue to compile.
    public let hasUserGen: Bool

    /// Stored properties declared in this decl's body, in source order.
    /// Empty for extensions, enums, actors, and any decl whose body
    /// the scanner didn't see (e.g. members declared in another file).
    /// Multi-binding lines like `let x: Int, y: Int` produce one entry
    /// per binding. Computed properties (those carrying an accessor
    /// block) and `static` / `class` properties are filtered out — the
    /// memberwise-Arbitrary derivation strategy reads only synthesised-
    /// init candidates. Defaults to `[]`.
    public let storedMembers: [StoredMember]

    /// `true` when this decl's body declares any `init(...)`. Swift
    /// suppresses the synthesised memberwise initializer in that case,
    /// so memberwise-Arbitrary derivation must fall through to `.todo`.
    /// Inits declared in extensions don't suppress synthesis, so the
    /// scanner sets this to `false` for `kind == .extension` regardless
    /// of the extension body. Defaults to `false`.
    public let hasUserInit: Bool

    public init(
        name: String,
        kind: Kind,
        inheritedTypes: [String],
        location: SourceLocation,
        hasUserGen: Bool = false,
        storedMembers: [StoredMember] = [],
        hasUserInit: Bool = false
    ) {
        self.name = name
        self.kind = kind
        self.inheritedTypes = inheritedTypes
        self.location = location
        self.hasUserGen = hasUserGen
        self.storedMembers = storedMembers
        self.hasUserInit = hasUserInit
    }
}
