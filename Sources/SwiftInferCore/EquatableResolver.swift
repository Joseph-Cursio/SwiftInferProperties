/// Three-valued evidence about whether a Swift type conforms to `Equatable`,
/// per PRD v0.3 §5.6's contradiction-detection scope. The `.notEquatable`
/// case is reserved for *clear* evidence (curated non-Equatable shapes);
/// `.unknown` is the default when textual analysis can't decide.
///
/// M3 plan open decision #1 calibrates the consumer policy: M3.4's
/// `ContradictionDetector` *drops* on `.notEquatable` and *keeps* on
/// `.unknown`, matching M1/M2's caveat-don't-drop posture.
public enum EquatableEvidence: Sendable, Equatable {
    case equatable
    case notEquatable
    case unknown
}

/// Best-effort textual `Equatable` classifier for the M3.3 layer. Built
/// from `ScannedCorpus.typeDecls` so corpus-declared `: Equatable` /
/// `: Hashable` / `: Comparable` types lift to `.equatable` without a
/// second AST walk.
///
/// Conditional-conformance reasoning (`Array<T>: Equatable where T:
/// Equatable`, `Optional<Wrapped>`, tuples, …) is intentionally out of
/// scope — that's a v1.1 constraint-engine concern (PRD §20.2). Generic /
/// optional / tuple types therefore classify as `.unknown` even when
/// their elements are Equatable. The exception is the curated
/// non-Equatable shape list (function types, `Any`, `AnyObject`, opaque
/// `some` / existential `any` prefixes), which veto regardless of nesting
/// because their textual signature cannot host value equality.
///
/// Per M3 plan open decision #2: extension `TypeDecl`s carry only the
/// conformances the extension adds, and the resolver merges multiple
/// records keyed by `name` — so `extension Foo: Equatable` declared in a
/// separate file lifts a `Foo` declared elsewhere.
public struct EquatableResolver: Sendable {

    /// Curated stdlib types known to conform to `Equatable`
    /// unconditionally. PRD §5.6 plan list: `Int`, `String`, `Bool`,
    /// `Double`, `Float`, fixed-width integer family, `UUID`, `Date`,
    /// `URL`. Internal so M3.6's tests can exercise the boundary.
    static let curatedEquatableStdlib: Set<String> = [
        "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Bool",
        "Float", "Double",
        "String",
        "UUID", "Date", "URL"
    ]

    /// Protocols whose presence in an inheritance clause implies
    /// `Equatable` conformance — `Hashable` and `Comparable` both refine
    /// `Equatable` in the standard library. Membership here is the only
    /// way M3 elevates a corpus type to `.equatable` without a literal
    /// `Equatable` token in its inheritance clause.
    static let knownEquatableConformance: Set<String> = [
        "Equatable", "Hashable", "Comparable"
    ]

    /// Set of corpus-declared type names that classify as `.equatable`,
    /// computed at init by folding all `TypeDecl`s by `name`. Names are
    /// stored verbatim — extension records carry the `extendedType` text,
    /// so `extension Array: Foo` keys under `"Array"`.
    private let corpusEquatable: Set<String>

    public init(typeDecls: [TypeDecl]) {
        var equatable: Set<String> = []
        for decl in typeDecls {
            let intersects = decl.inheritedTypes.contains { Self.knownEquatableConformance.contains($0) }
            if intersects {
                equatable.insert(decl.name)
            }
        }
        self.corpusEquatable = equatable
    }

    /// Classifies a Swift type written as source text. Resolution order:
    /// 1. Curated non-Equatable shape match → `.notEquatable`.
    /// 2. Curated stdlib match → `.equatable`.
    /// 3. Corpus-derived match → `.equatable`.
    /// 4. Otherwise → `.unknown`.
    public func classify(typeText: String) -> EquatableEvidence {
        let trimmed = typeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.isProvablyNonEquatable(trimmed) {
            return .notEquatable
        }
        if Self.curatedEquatableStdlib.contains(trimmed) {
            return .equatable
        }
        if corpusEquatable.contains(trimmed) {
            return .equatable
        }
        return .unknown
    }

    /// Textual detector for the curated non-Equatable shapes. Generics
    /// use `<...>` and tuples use `(...,)` in valid Swift type syntax, so
    /// `->` is unambiguous as the function-type marker — `[(Int) -> Int]`
    /// also matches and is correctly classified as non-Equatable.
    /// Open decision #3 in the M3 plan accepts the typealias false
    /// negative (`typealias Handler = (Int) -> Void` then `param: Handler`
    /// won't match) until v1.1 semantic resolution.
    static func isProvablyNonEquatable(_ trimmed: String) -> Bool {
        if trimmed == "Any" || trimmed == "AnyObject" { return true }
        if trimmed.contains("->") { return true }
        if trimmed.hasPrefix("some ") { return true }
        if trimmed.hasPrefix("any ") { return true }
        return false
    }
}
