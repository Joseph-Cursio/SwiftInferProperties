import Foundation

/// V1.145 — a curated catalog of **known-true** algebraic properties on
/// standard-library types, plus the famous **caveats** (properties that
/// look plausible but do NOT hold). Shipped built-in with the engine
/// (universal, versioned) — deliberately NOT written into any project's
/// `.swiftinfer/`, which stays the user's own discovered corpus.
///
/// These are the one class of property that is both *known-true by contract*
/// and *verifiable* (their carriers — `Int`, `String`, `[T]`, `Set`, `Bool`
/// — are exactly the ones the generator can construct), so `--verify` can
/// confirm them live rather than assert them. The caveats encode the same
/// counter-signals the scoring engine already knows (`Double.+` is not
/// associative; `String`/`Array` `+` is not commutative).
public enum KnownPropertyKind: String, Sendable, Equatable {
    case law      // known-true; carries a `checkBody` so `--verify` can run it
    case caveat   // a plausible-looking NON-property; documented, never asserted true
}

public struct KnownProperty: Sendable, Equatable {
    public let type: String
    public let structure: String
    public let statement: String
    public let kind: KnownPropertyKind
    public let note: String?
    /// A Swift expression (returning `Bool`) over the catalog's `rand*`
    /// helpers, run under `--verify`. `nil` for caveats.
    public let checkBody: String?

    public var displayName: String { "\(type): \(statement)" }
}

public enum StandardLibraryProperties {

    public static let laws: [KnownProperty] = all.filter { $0.kind == .law }
    public static let caveats: [KnownProperty] = all.filter { $0.kind == .caveat }

    // Int — additive monoid + max/min semilattice
    private static let intLaws: [KnownProperty] = [
        law(
            "Int", "commutative monoid under +", "a + b == b + a",
            "let a = randInt(), b = randInt(); return a + b == b + a"
        ),
        law(
            "Int", "commutative monoid under +", "(a + b) + c == a + (b + c)",
            "let a = randInt(), b = randInt(), c = randInt(); return (a + b) + c == a + (b + c)"
        ),
        law(
            "Int", "additive identity", "a + 0 == a",
            "let a = randInt(); return a + 0 == a"
        ),
        law(
            "Int", "commutative semilattice under max", "max(a, b) == max(b, a)",
            "let a = randInt(), b = randInt(); return max(a, b) == max(b, a)"
        ),
        law(
            "Int", "commutative semilattice under max", "max(max(a, b), c) == max(a, max(b, c))",
            "let a = randInt(), b = randInt(), c = randInt(); return max(max(a, b), c) == max(a, max(b, c))"
        ),
        law(
            "Int", "idempotent under max", "max(a, a) == a",
            "let a = randInt(); return max(a, a) == a"
        ),
        law(
            "Int", "idempotent", "abs(abs(a)) == abs(a)",
            "let a = randInt(); return abs(abs(a)) == abs(a)"
        )
    ]

    // Double — floating point holds the commutative/identity laws ONLY for
    // finite inputs (NaN/±∞ break them under ==), and is NOT associative even
    // for finite values (see caveats). Listed explicitly so its special-case
    // status is visible rather than read as an oversight.
    private static let doubleLaws: [KnownProperty] = [
        law(
            "Double", "commutative under + (finite inputs)", "a + b == b + a",
            "let a = randDouble(), b = randDouble(); return a + b == b + a",
            note: "Finite inputs only — NaN/±∞ break these under ==, and + is NOT associative (see caveats)."
        ),
        law(
            "Double", "commutative under * (finite inputs)", "a * b == b * a",
            "let a = randDouble(), b = randDouble(); return a * b == b * a"
        ),
        law(
            "Double", "additive identity (finite inputs)", "a + 0.0 == a",
            "let a = randDouble(); return a + 0.0 == a"
        ),
        law(
            "Double", "multiplicative identity (finite inputs)", "a * 1.0 == a",
            "let a = randDouble(); return a * 1.0 == a"
        )
    ]

    // Bool — boolean algebra
    private static let boolLaws: [KnownProperty] = [
        law(
            "Bool", "commutative under &&", "(a && b) == (b && a)",
            "let a = randBool(), b = randBool(); return (a && b) == (b && a)"
        ),
        law(
            "Bool", "associative under ||", "((a || b) || c) == (a || (b || c))",
            "let a = randBool(), b = randBool(), c = randBool(); return ((a || b) || c) == (a || (b || c))"
        ),
        law(
            "Bool", "idempotent under &&", "(a && a) == a",
            "let a = randBool(); return (a && a) == a"
        )
    ]

    // String — free monoid under concatenation
    private static let stringLaws: [KnownProperty] = [
        law(
            "String", "monoid under + (NOT commutative)", "(a + b) + c == a + (b + c)",
            "let a = randStr(), b = randStr(), c = randStr(); return (a + b) + c == a + (b + c)"
        ),
        law(
            "String", "concatenation identity", "a + \"\" == a",
            "let a = randStr(); return a + \"\" == a"
        )
    ]

    // Array — free monoid + reverse involution + sort idempotence
    private static let arrayLaws: [KnownProperty] = [
        law(
            "Array", "reverse is an involution", "a.reversed().reversed() == a",
            "let a = randArr(); return Array(a.reversed().reversed()) == a"
        ),
        law(
            "Array", "idempotent under sort", "a.sorted().sorted() == a.sorted()",
            "let a = randArr(); return a.sorted().sorted() == a.sorted()"
        ),
        law(
            "Array", "monoid under + (NOT commutative)", "(a + b) + c == a + (b + c)",
            "let a = randArr(), b = randArr(), c = randArr(); return (a + b) + c == a + (b + c)"
        )
    ]

    // Set — bounded semilattice under union / intersection
    private static let setLaws: [KnownProperty] = [
        law(
            "Set", "commutative under union", "a.union(b) == b.union(a)",
            "let a = randSet(), b = randSet(); return a.union(b) == b.union(a)"
        ),
        law(
            "Set", "associative under union", "a.union(b).union(c) == a.union(b.union(c))",
            "let a = randSet(), b = randSet(), c = randSet(); return a.union(b).union(c) == a.union(b.union(c))"
        ),
        law(
            "Set", "idempotent under union", "a.union(a) == a",
            "let a = randSet(); return a.union(a) == a"
        ),
        law(
            "Set", "commutative under intersection", "a.intersection(b) == b.intersection(a)",
            "let a = randSet(), b = randSet(); return a.intersection(b) == b.intersection(a)"
        )
    ]

    // Caveats — plausible-looking NON-properties (never asserted true)
    private static let caveatEntries: [KnownProperty] = [
        caveat(
            "String", "+ is NOT commutative",
            "`a + b != b + a` in general — concatenation is ordered."
        ),
        caveat(
            "Array", "+ is NOT commutative",
            "`a + b != b + a` in general — concatenation is ordered."
        ),
        caveat(
            "Double", "+ is NOT associative",
            "IEEE-754 rounding: `(a + b) + c != a + (b + c)` for some values."
        ),
        caveat(
            "Set", "subtracting is NOT commutative",
            "`a.subtracting(b) != b.subtracting(a)` in general."
        ),
        caveat(
            "Bool", "&& / || short-circuit — laws hold for VALUES, not evaluation",
            "Swift does not evaluate the right operand when the left decides the result, "
                + "so with side effects `a && f()` and `f() && a` differ in what runs."
        )
    ]

    public static let all: [KnownProperty] =
        intLaws + doubleLaws + boolLaws + stringLaws + arrayLaws + setLaws + caveatEntries

    // MARK: - Builders

    private static func law(
        _ type: String,
        _ structure: String,
        _ statement: String,
        _ checkBody: String,
        note: String? = nil
    ) -> KnownProperty {
        KnownProperty(
            type: type, structure: structure, statement: statement,
            kind: .law, note: note, checkBody: checkBody
        )
    }

    private static func caveat(_ type: String, _ statement: String, _ note: String) -> KnownProperty {
        KnownProperty(
            type: type, structure: statement, statement: statement,
            kind: .caveat, note: note, checkBody: nil
        )
    }
}
