import PropertyLawCore

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

    // Intentionally a superset of `IndexedTypeShape.Kind` — both mirror
    // `PropertyLawCore.TypeShape.Kind`, and this one adds `.extension` for the reason given
    // above. The extra case is the point, not a divergence to reconcile.
    // swiftprojectlint:disable:next parallel-list-drift
    /// Surface-syntactic kind of the source declaration. Mirrors
    /// `PropertyLawCore.TypeShape.Kind` for `struct` / `class` / `enum` /
    /// `actor`, and adds `.extension` so extension conformances stay
    /// distinguishable from primary declarations during resolver merging.
    public enum Kind: String, Sendable, Equatable {
        case `struct`
        case `class`
        case `enum`
        case `actor`
        case `extension`
        /// A protocol declaration. Recorded for its **inheritance clause only** — the body is
        /// still skipped, because requirements have no implementations to summarise.
        ///
        /// Added 2026-07-30. Protocols were skipped outright, so a protocol's refinements were
        /// invisible: `ProtocolCoverageMap` could not see that `BinaryInteger` refines
        /// `Strideable` (`Integers.swift:533`), and therefore **no coverage veto could ever
        /// fire on a protocol-extension carrier**. Measured before the fix: 6 typeDecls named
        /// `BinaryInteger`, every one with `inheritedTypes == []`.
        case `protocol`
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

    /// TestLifter M14.0 — case identifiers declared in this decl's
    /// member block, in source order. Populated for `kind == .enum`
    /// (and `kind == .extension` over an enum, when the extension
    /// adds cases). Empty for non-enum kinds, for enums with no
    /// declared cases, and for any decl whose body the scanner didn't
    /// see. Multi-binding case lines (`case small, medium, large`)
    /// produce one entry per binding. Associated-value parameter
    /// clauses (`case small(Int)`) and raw-value initializers
    /// (`case small = "S"`) are stripped — only the case identifier
    /// is retained. Consumed by `NClassEquivalenceClassDetector`
    /// (M14.1) for the M13 plan §"What M13 ships" axis 4 same-target
    /// exhaustiveness check.
    public let enumCaseNames: [String]

    /// User-declared initializer signatures (primary struct decls). Feeds the
    /// Tier 6 `initializerBased` derivation when the synthesized memberwise
    /// init is suppressed. Empty for non-structs and extension records.
    public let initializers: [InitializerSignature]

    /// Enum cases with associated values (primary enum decls). Feeds the
    /// Tier 4 `enumCases` derivation. Distinct from `enumCaseNames`, which is
    /// names-only for the M14 exhaustiveness detector.
    public let enumCases: [EnumCase]

    /// The declaration's name **prefixed by its enclosing types**, dot-joined —
    /// `IndexedTypeShape.Kind` for a `Kind` nested inside `IndexedTypeShape`,
    /// and identical to `name` for a top-level type.
    ///
    /// **Why this exists.** `name` alone is not a key. This repo declares eight
    /// distinct types called `Kind`, seven called `Visitor`, and six called
    /// `CodingKeys`, and `TypeShapeBuilder` used to group decls by `name` — so
    /// those eight `Kind`s merged into a single group whose primary was whichever
    /// file happened to be scanned first, and a member typed `Kind` on one type
    /// could be generated from an unrelated type's nested enum. The generated
    /// stub then either failed to compile (the name isn't in scope from the
    /// verifier) or, worse, compiled against the wrong type.
    ///
    /// Measured on this repo before the change: 218 shape entries, 13 of which
    /// carried more than one source declaration. See
    /// `docs/measurements/roadtest-self-dogfood.md` §11.1.
    ///
    /// `name` is deliberately kept bare — `containingTypeName` matching, template
    /// vocabularies, and identity hashes all key on the simple name, and
    /// re-pointing those is a separate change. This field is additive.
    public let qualifiedName: String

    /// The declaration's generic parameters, in order, with each one's inheritance
    /// constraint if it wrote one — `Boxy<Element: Hashable>` gives
    /// `[("Element", "Hashable")]`.
    ///
    /// **Captured 2026-08-02 because nothing captured it.** `name` is `node.name.text`, the
    /// bare identifier, so a generic carrier was indistinguishable from a concrete one all
    /// the way to emission. `scaffold-kit-suites` wrote `Deque.self` and `PersistentSet.self`
    /// — neither typechecks — and no derived generator for a generic carrier could ever have
    /// compiled. Empty for non-generic declarations, which is the overwhelming majority.
    public let genericParameters: [GenericParameter]

    /// The declaration's own access level, as `FunctionScannerVisitor.access(of:)` reads it.
    ///
    /// **`.notVisibleToTests` means `@testable import` cannot reach this type**, because
    /// `@testable` raises `internal` to public and leaves `private` / `fileprivate` alone. A
    /// consumer that emits code naming the type — `scaffold-kit-suites` does — must decline it
    /// rather than emit a call that cannot compile.
    ///
    /// **The scanner already computed this and dropped it.** `enclosingTypeAccess` has tracked
    /// the same value on a stack since the access-restriction work; it was never put on the
    /// record the emitters read, so `scaffold-kit-suites` emitted a LIVE suite for
    /// `Euclid`'s `private struct IndexPair` — worth all 40 of that subject's remaining compile
    /// errors (`docs/measurements/kit-scaffold-conversion.md` §3.1).
    ///
    /// Defaults to `true` so every existing construction site and hand-built test fixture
    /// compiles unchanged, and so a consumer that does not ask sees the behaviour it had before.
    ///
    /// **A `Bool` rather than the scanner's tri-state**, because the only question any consumer
    /// asks of it is *can emitted code name this type*, and `EnclosingTypeAccess` is internal to
    /// `FunctionScannerVisitor`. Widening that enum to publish a distinction nobody needs would
    /// be the wrong half of the trade.
    public let isVisibleToTestableImport: Bool

    /// `true` for an extension record written with a `where` clause
    /// (`extension Deque where Element: Hashable`). Always false for a primary declaration.
    ///
    /// **Captured so extension-declared initializers can be merged safely.** An initializer
    /// on an unconditional extension is callable on the type, full stop; one on a
    /// conditional extension may not apply to the instantiation the emitter chose, and
    /// calling it would emit code that does not compile. swift-collections has 267
    /// conditional extensions, so the distinction is not hypothetical.
    public let isConditionalExtension: Bool

    /// One generic parameter and the constraint written on it, if any.
    public struct GenericParameter: Sendable, Equatable {
        public let name: String
        /// The inheritance clause as written (`Hashable`, `Comparable`, …), or `nil` for an
        /// unconstrained parameter. Textual, matching this file's posture elsewhere.
        public let constraint: String?

        public init(name: String, constraint: String?) {
            self.name = name
            self.constraint = constraint
        }
    }

    public init(
        name: String,
        kind: Kind,
        inheritedTypes: [String],
        location: SourceLocation,
        hasUserGen: Bool = false,
        storedMembers: [StoredMember] = [],
        hasUserInit: Bool = false,
        enumCaseNames: [String] = [],
        initializers: [InitializerSignature] = [],
        enumCases: [EnumCase] = [],
        qualifiedName: String? = nil,
        genericParameters: [GenericParameter] = [],
        isConditionalExtension: Bool = false,
        isVisibleToTestableImport: Bool = true
    ) {
        // Defaulted to `name` so the many hand-built test fixtures — and any
        // caller that has no enclosing-type context — keep working unchanged.
        self.qualifiedName = qualifiedName ?? name
        self.name = name
        self.genericParameters = genericParameters
        self.isConditionalExtension = isConditionalExtension
        self.kind = kind
        self.inheritedTypes = inheritedTypes
        self.location = location
        self.hasUserGen = hasUserGen
        self.storedMembers = storedMembers
        self.hasUserInit = hasUserInit
        self.enumCaseNames = enumCaseNames
        self.initializers = initializers
        self.enumCases = enumCases
        self.isVisibleToTestableImport = isVisibleToTestableImport
    }
}
