/// Three-valued evidence about whether a Swift type conforms to `Equatable`,
/// per PRD §5.6's contradiction-detection scope. The `.notEquatable`
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
/// General conditional-conformance reasoning stays out of scope — that's a v1.1
/// constraint-engine concern (PRD §20.2). Two shapes are handled anyway, because
/// for them the "condition" is a rewrite rather than a judgement: `Array<T>` and
/// `Optional<T>` are `Equatable` exactly when `T` is, so the container simply
/// inherits its payload's verdict. `Set`, `Dictionary` and tuples are still
/// `.unknown` — their conformances rest on different constraints (see
/// `singlePayloadElement`).
///
/// The curated non-Equatable shape list (function types, `Any`, `AnyObject`,
/// opaque `some` / existential `any` prefixes) vetoes regardless of nesting,
/// because its textual signature cannot host value equality — and it is
/// consulted before the payload rewrite, so `[Any]` refutes rather than
/// unwrapping to a bare `Any`.
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
    ///
    /// `Data` added from the MacCloud_client_MacOS road-test (2026-07-18): a
    /// `(Data) throws -> Data` encrypt/decrypt round-trip is a flagship property,
    /// but `Data` (Foundation, unconditionally `Equatable`) classified `.unknown`,
    /// demoting it out of `RoundTripTemplate` into the weaker inverse-pair tier.
    /// It's as common a round-trip carrier as `String`/`URL` (encrypt/decrypt,
    /// serialize/deserialize, compress/decompress).
    static let curatedEquatableStdlib: Set<String> = FixedWidthIntegerNames.names.union([
        "Bool",
        "Float", "Double",
        "String",
        "UUID", "Date", "URL",
        "Data"
    ])

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
    /// 4. Single-payload container (`[T]` / `T?`) → classify `T`.
    /// 5. Otherwise → `.unknown`.
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
        // `Array` and `Optional` conform to `Equatable` exactly when their
        // payload does, so the container's verdict IS the payload's verdict —
        // including `.notEquatable`, which is why `[Any]` and `((Int) -> Int)?`
        // come back refuted rather than merely unknown.
        if let payload = Self.singlePayloadElement(of: trimmed) {
            return classify(typeText: payload)
        }
        return .unknown
    }

    /// The payload of a single-element container spelling, or `nil` when
    /// `trimmed` is not one.
    ///
    /// **Why only `Array` and `Optional`.** Both are `Equatable` under exactly
    /// one condition — their single payload is — so the rule is a rewrite, not
    /// a judgement. `Set` and `Dictionary` are deliberately excluded: their
    /// conditional conformances rest on *different* constraints (`Set` needs
    /// `Element: Hashable`, `Dictionary` needs `Value: Equatable` with the key
    /// already `Hashable`), and tuples are not nominal types and cannot conform
    /// at all. Folding those in would need the constraint engine PRD §20.2
    /// defers, not this rewrite.
    ///
    /// Recursion falls out for free — `[String?]` strips to `String?` strips to
    /// `String` — and terminates because every step shortens the text.
    static func singlePayloadElement(of trimmed: String) -> String? {
        // `T?` / `T!`. Both spellings are `Optional` underneath.
        if trimmed.count > 1, trimmed.hasSuffix("?") || trimmed.hasSuffix("!") {
            return String(trimmed.dropLast())
        }
        // `[T]`, but not `[Key: Value]`.
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
            let inner = String(trimmed.dropFirst().dropLast())
            return hasTopLevelColon(inner) ? nil : inner
        }
        // The long-form spellings of the same two types.
        for prefix in ["Array<", "Optional<"] where trimmed.hasPrefix(prefix) && trimmed.hasSuffix(">") {
            return String(trimmed.dropFirst(prefix.count).dropLast())
        }
        return nil
    }

    /// Whether `text` contains a `:` outside any bracket nesting — the marker
    /// that separates a dictionary's key from its value. Depth-tracked so
    /// `[[String: Int]]` is still recognised as an array of dictionaries
    /// rather than mistaken for a dictionary itself.
    private static func hasTopLevelColon(_ text: String) -> Bool {
        var depth = 0
        for character in text {
            switch character {
            case "<", "[", "(": depth += 1
            case ">", "]", ")": depth -= 1
            case ":" where depth == 0: return true
            default: break
            }
        }
        return false
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
