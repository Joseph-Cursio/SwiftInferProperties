import PropertyLawCore

/// Classification of a candidate function's containing-type carrier per
/// the v1.18 plan workstream A. Drives the `referenceTypeCarrier` /
/// `valueSemanticCarrier` signals across `IdempotenceTemplate`,
/// `RoundTripTemplate`, `InversePairTemplate`, and `IdentityElementTemplate`.
///
/// The classification is intentionally **textual + structural** — it consumes
/// the same `TypeDecl` records the M3 / M4 resolvers already use and never
/// invokes type-resolution. This is a pre-SemanticIndex approximation that
/// matches `EquatableResolver`'s and `ProtocolCoverageMap`'s posture.
///
/// Conservative bias: when the resolver cannot make a confident call (member
/// type unresolved, recursion-depth budget exhausted, mixed value/reference
/// composition), it returns `.unknown` — the templates emit no signal in
/// that case rather than guessing. The negative `.referenceType` magnitude
/// is intentionally larger than the positive `.valueSemantic` magnitude
/// because false positives on reference types are sharper bugs than missed
/// value-semantic positives.
public enum CarrierKind: Sendable, Equatable {
    /// `kind == .struct || .enum` AND every recursively-resolved stored
    /// member is value-semantic (curated stdlib value type, generic
    /// parameter, container of value-semantic types, or another
    /// value-semantic struct/enum in the same corpus).
    case valueSemantic
    /// `kind == .class || .actor` — aliasing-sensitive carrier.
    case referenceType
    /// `kind == .struct || .enum` but at least one stored member resolves
    /// to a reference type or a closure type, breaking the value-semantic
    /// guarantee per `docs/ideas/ValueSemantic Kit Proposal.md` §2.2
    /// worked examples 1 (NSMutableArray container) + 3 (closure capturing
    /// shared state). Templates emit no signal in this case — conservative.
    case mixed
    /// Top-level function (no containing type), or the type name doesn't
    /// resolve to any `TypeDecl` in the corpus, or the recursive
    /// classification ran out of depth budget. Templates emit no signal.
    case unknown
}

/// Same-file-only resolver per the v1.18 plan open decision #1 lean. Built
/// once per `TemplateRegistry.discover` call from the corpus `[TypeDecl]`
/// and threaded into the four suggestion-emitting templates.
///
/// **Same-file scope.** The plan revisits cross-file scope at v1.20 if the
/// empirical data shows a meaningful corpus of cross-file value-semantic
/// struct carriers being missed. The same-file posture matches
/// `TypeShapeBuilder`'s current behavior and avoids the corpus-wide
/// resolver complexity that `EquatableResolver` carries.
///
/// **Recursion bound.** Stored-member classification recurses through
/// nested struct types up to depth 3. Beyond that the resolver returns
/// `.unknown` — deeper compositions are vanishingly rare in idiomatic
/// Swift and bounding the recursion guarantees the resolver is O(N) over
/// the corpus.
public struct CarrierKindResolver: Sendable {

    private let typeDeclsByName: [String: [TypeDecl]]

    public init(typeDecls: [TypeDecl]) {
        var map: [String: [TypeDecl]] = [:]
        for decl in typeDecls {
            map[decl.name, default: []].append(decl)
        }
        self.typeDeclsByName = map
    }

    /// Classify `typeName` per `CarrierKind`. `nil` (top-level function)
    /// returns `.unknown` — top-level functions have no carrier so the
    /// signal doesn't apply.
    public func classify(typeName: String?) -> CarrierKind {
        guard let typeName, !typeName.isEmpty else { return .unknown }
        return classify(typeName: typeName, depth: 0)
    }

    private func classify(typeName: String, depth: Int) -> CarrierKind {
        let stripped = Self.strippingGenericParameters(typeName)
        if let leaf = Self.classifyLeaf(stripped) {
            return leaf
        }
        guard let decls = typeDeclsByName[stripped] else {
            return .unknown
        }
        return classifyDecls(decls, depth: depth)
    }

    /// Classify a textually-leaf type — curated allow-list, tuple/literal
    /// syntax, generic-parameter heuristic. Returns `nil` when none apply
    /// (caller falls through to corpus `TypeDecl` lookup).
    private static func classifyLeaf(_ stripped: String) -> CarrierKind? {
        // Curated stdlib value-type allow-list (post-generic-stripping).
        if curatedValueTypes.contains(stripped) {
            return .valueSemantic
        }
        // Tuple syntax `(Int, String)` — value-semantic by language rules.
        // Array / dictionary literal syntax `[Int]` / `[K: V]` — same.
        if stripped.hasPrefix("(") || stripped.hasPrefix("[") {
            return .valueSemantic
        }
        // Generic parameters (single uppercase letter or `T1`/`U2`
        // convention) — assumed value-semantic per stdlib convention.
        // The PRD §11 generator strategist makes the same assumption when
        // synthesising `Arbitrary` for a generic carrier.
        if isLikelyGenericParameter(stripped) {
            return .valueSemantic
        }
        return nil
    }

    /// Classify a corpus-known type from its `TypeDecl` records (primary +
    /// extensions). Reference-kind wins over extension records; struct/enum
    /// kinds defer to `classifyMembers`.
    private func classifyDecls(_ decls: [TypeDecl], depth: Int) -> CarrierKind {
        let kinds = Set(decls.map(\.kind))
        if kinds.contains(.class) || kinds.contains(.actor) {
            return .referenceType
        }
        // Aggregate stored members across all decls. Swift forbids stored
        // properties in extensions of types declared elsewhere, but the
        // scanner records primary + extension uniformly — flat aggregation
        // is safe.
        return classifyMembers(decls.flatMap(\.storedMembers), depth: depth)
    }

    private func classifyMembers(_ allStoredMembers: [StoredMember], depth: Int) -> CarrierKind {
        // Closure-typed stored member → reference-leaking risk per
        // `docs/ideas/ValueSemantic Kit Proposal.md` §2.2 example 3.
        // Closures capture by reference; struct copies share the closure's
        // captured `var` state.
        if allStoredMembers.contains(where: { Self.isClosureType($0.typeName) }) {
            return .mixed
        }
        // Empty-stored-properties struct/enum (or members not visible to
        // the scanner) — value-semantic by default. Pure-enum cases are
        // value-semantic, and a struct with no fields is trivially so.
        if allStoredMembers.isEmpty {
            return .valueSemantic
        }
        // Recursion-depth bound. Beyond depth 3 we give up — the
        // composition is too deep to reason about textually.
        if depth >= 3 {
            return .unknown
        }
        var hasUnknownMember = false
        for member in allStoredMembers {
            switch classify(typeName: member.typeName, depth: depth + 1) {
            case .valueSemantic:
                continue

            case .referenceType, .mixed:
                return .mixed

            case .unknown:
                hasUnknownMember = true
            }
        }
        // All members resolved value-semantic → parent is value-semantic.
        // At least one unknown (and no reference/mixed) → parent is
        // unknown (conservative; can't make a positive claim).
        return hasUnknownMember ? .unknown : .valueSemantic
    }

    /// Curated stdlib value-type allow-list (post-generic-stripping). The
    /// same set the v1.5 `ProtocolCoverageMap.strippingGenericParameters`
    /// rule operates on — types whose stdlib definition guarantees value
    /// semantics. Vocabulary extension lands at v1.21+ (open decision #6
    /// in the v1.18 plan).
    static let curatedValueTypes: Set<String> = [
        // Integer
        "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        // Boolean / Floating
        "Bool",
        "Double", "Float", "Float16", "Float32", "Float64", "Float80",
        "CGFloat",
        // String + Character
        "String", "Substring", "Character", "StaticString", "Unicode.Scalar",
        // Foundation core values
        "Data", "Date", "URL", "UUID", "Decimal",
        "TimeInterval", "TimeZone", "Locale", "Calendar",
        // Stdlib generic value containers (post-stripping these become
        // their bare names — `Array<T>` -> `Array`, etc.)
        "Optional", "Result",
        "Range", "ClosedRange",
        "PartialRangeFrom", "PartialRangeUpTo", "PartialRangeThrough",
        "Array", "Dictionary", "Set",
        "ContiguousArray", "ArraySlice",
        "KeyValuePairs", "EmptyCollection", "CollectionOfOne",
        // swift-collections
        "OrderedSet", "OrderedDictionary", "Deque",
        // Modern stdlib
        "Duration", "Measurement", "Unit",
        // Misc
        "AnyHashable", "ObjectIdentifier", "PartialKeyPath", "KeyPath",
        "WritableKeyPath", "ReferenceWritableKeyPath"
    ]

    /// Strip a single generic-parameter list from a textual type name.
    /// Mirrors `ProtocolCoverageMap.strippingGenericParameters` so the two
    /// resolvers agree on lookup keys.
    public static func strippingGenericParameters(_ name: String) -> String {
        guard let openAngle = name.firstIndex(of: "<") else { return name }
        return String(name[..<openAngle])
    }

    /// Heuristic: a single uppercase letter (`T`, `U`), or an uppercase
    /// letter followed by digits (`T1`, `U2`), or an uppercase letter
    /// followed by a lowercase tail commonly used for generic params
    /// (`Element`, `Wrapped`, `Key`, `Value`). The last bucket is the
    /// fuzziest — it intentionally folds in stdlib generic-parameter names
    /// like `Element` so e.g. `Array<Element>` stripped to `Array` and
    /// then a future hypothetical member typed `Element` still classifies
    /// value-semantic.
    static func isLikelyGenericParameter(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        // Single uppercase letter
        if name.count == 1, name.first?.isUppercase == true {
            return true
        }
        // T1, U2, etc.
        if name.count == 2,
           name.first?.isUppercase == true,
           name.last?.isNumber == true {
            return true
        }
        // Curated stdlib generic-parameter names.
        return Self.curatedGenericParameterNames.contains(name)
    }

    /// Curated stdlib generic-parameter names — kept conservative on
    /// purpose. Adding a name here treats it as "assume value-semantic if
    /// referenced as a stored-property type."
    private static let curatedGenericParameterNames: Set<String> = [
        "Element", "Wrapped", "Key", "Value", "Failure", "Success",
        "Bound", "Index", "Iterator", "SubSequence", "Indices"
    ]

    /// Textual closure-type detection: `(...) -> ...`, optionally prefixed
    /// by attributes like `@escaping`, `@Sendable`, `@MainActor`. The
    /// scanner records member types as `trimmedDescription`, so attribute
    /// prefixes appear verbatim.
    static func isClosureType(_ typeName: String) -> Bool {
        var trimmed = typeName.trimmingCharacters(in: .whitespaces)
        // Strip leading attribute clauses one at a time. Attributes can
        // be parameterised (`@MainActor`, `@Sendable`); we only need to
        // skip past the leading `@<word>` tokens to expose the core type.
        while trimmed.hasPrefix("@") {
            guard let space = trimmed.firstIndex(of: " ") else { break }
            trimmed = String(trimmed[trimmed.index(after: space)...])
                .trimmingCharacters(in: .whitespaces)
        }
        // Function types always contain `->`. Trailing-throws and async
        // forms preserve the arrow.
        return trimmed.contains("->")
    }

    // MARK: - Signal factory

    /// Carrier-kind signal for a function summary's containing type. Returns
    /// `nil` when classification is `.mixed` or `.unknown` (templates emit
    /// no signal in those cases — conservative posture per the v1.18 plan).
    /// `weight` and `kind` follow the plan: value-semantic = `+5`,
    /// reference-type = `-10`.
    public func carrierKindSignal(
        forContainingTypeName typeName: String?
    ) -> Signal? {
        switch classify(typeName: typeName) {
        case .valueSemantic:
            let label = typeName.map { " (\($0))" } ?? ""
            return Signal(
                kind: .valueSemanticCarrier,
                weight: 5,
                detail: "Value-semantic carrier\(label) — algebraic property "
                    + "is well-defined under aliasing"
            )

        case .referenceType:
            let label = typeName.map { " (\($0))" } ?? ""
            return Signal(
                kind: .referenceTypeCarrier,
                weight: -10,
                detail: "Reference-type carrier\(label) — class/actor; "
                    + "algebraic properties may be aliasing-sensitive "
                    + "(shared state through stored references)"
            )

        case .mixed, .unknown:
            return nil
        }
    }
}
