import Foundation

/// V1.145 — a curated catalog of **known-true** algebraic properties on
/// standard-library types, plus the famous **caveats** (properties that
/// look plausible but do NOT hold). Shipped built-in with the engine
/// (universal, versioned) — deliberately NOT written into any project's
/// `.swiftinfer/`, which stays the user's own discovered corpus.
///
/// These are the one class of property that is both *known-true by contract*
/// and *verifiable* (their carriers — `Int`, `Double`, `Bool`, `String`,
/// `[T]`, `Set`, `Optional`, `Dictionary` — are exactly the ones the generator
/// can construct), so `--verify` can confirm them live rather than assert them.
///
/// Each law is tagged with the **SwiftPropertyLaws protocol it witnesses**
/// (`Semigroup` / `Monoid` / `CommutativeMonoid` / `Semilattice`) — the
/// upstream kit protocol a conforming type satisfies. A law tags a protocol
/// only when the *whole structure* conforms: `Double.+` is commutative with
/// an identity but is NOT associative, so it witnesses no protocol (it is not
/// a `Monoid`); unary idempotence / involutions aren't algebraic protocols
/// either, so they tag none.
public enum KnownPropertyKind: String, Sendable, Equatable {
    case law      // known-true; carries a `checkBody` so `--verify` can run it
    case caveat   // a plausible-looking NON-property; documented, never asserted true
}

/// Whether an entry does confidence work in `discover`, or is documentation.
///
/// The catalog serves two masters and they must be told apart, or reference
/// laws masquerade as enforced ones. An entry `anchor`s iff it carries a
/// `template` a discovered candidate can match (`StdlibAnchor` keys on
/// `template == candidate.templateName`): a `.law` becomes a "proven analog"
/// line, a `.caveat` becomes a "known counter-example" line. Everything else is
/// `.reference` — true and self-verifiable, but invisible to `discover` because
/// no template names its shape (functor / stack / queue / involution laws). The
/// role is DERIVED from `template`, so it cannot drift: the day a shape gets a
/// template, its entries stop being reference and start anchoring.
public enum KnownPropertyRole: String, Sendable, Equatable {
    case anchor      // feeds StdlibAnchor — a proven analog (law) or a trap (caveat)
    case reference   // documentation + self-check only; `discover` never consults it
}

public struct KnownProperty: Sendable, Equatable {
    public let type: String
    public let structure: String
    public let statement: String
    public let kind: KnownPropertyKind
    /// Whether `discover` consults this entry (`.anchor`) or it is pure
    /// documentation (`.reference`). Derived from `template` by the builders.
    public let role: KnownPropertyRole
    /// The SwiftPropertyLaws kit protocol this law witnesses (e.g.
    /// `"CommutativeMonoid"`), or `nil` when the structure conforms to no
    /// kit protocol (see the type doc for the Double / unary cases).
    public let witnesses: String?
    /// The `discover` template family this entry corresponds to (e.g.
    /// `"commutativity"`), so the stdlib anchor can match a discovered
    /// candidate's `(templateName, carrier)` to a proven analog (a law) or
    /// trap (a caveat). `nil` when it maps to no single template.
    public let template: String?
    public let note: String?
    /// A Swift expression (returning `Bool`) over the catalog's `rand*`
    /// helpers, run under `--verify`. `nil` for caveats.
    public let checkBody: String?

    public var displayName: String { "\(type): \(statement)" }
}

public enum StandardLibraryProperties {

    public static let laws: [KnownProperty] = all.filter { $0.kind == .law }
    public static let caveats: [KnownProperty] = all.filter { $0.kind == .caveat }

    // Int — additive commutative monoid + max semilattice
    private static let intLaws: [KnownProperty] = [
        law(
            "Int", "commutative monoid under +", "a + b == b + a",
            "let a = randInt(), b = randInt(); return a + b == b + a",
            witnesses: "CommutativeMonoid", template: "commutativity"
        ),
        law(
            "Int", "commutative monoid under +", "(a + b) + c == a + (b + c)",
            "let a = randInt(), b = randInt(), c = randInt(); return (a + b) + c == a + (b + c)",
            witnesses: "CommutativeMonoid", template: "associativity"
        ),
        law(
            "Int", "additive identity", "a + 0 == a",
            "let a = randInt(); return a + 0 == a",
            witnesses: "CommutativeMonoid"
        ),
        law(
            "Int", "semilattice under max", "max(a, b) == max(b, a)",
            "let a = randInt(), b = randInt(); return max(a, b) == max(b, a)",
            witnesses: "Semilattice"
        ),
        law(
            "Int", "semilattice under max", "max(max(a, b), c) == max(a, max(b, c))",
            "let a = randInt(), b = randInt(), c = randInt(); return max(max(a, b), c) == max(a, max(b, c))",
            witnesses: "Semilattice"
        ),
        law(
            "Int", "idempotent under max", "max(a, a) == a",
            "let a = randInt(); return max(a, a) == a",
            witnesses: "Semilattice"
        ),
        law(
            "Int", "idempotent unary function", "abs(abs(a)) == abs(a)",
            "let a = randInt(); return abs(abs(a)) == abs(a)"
        )
    ]

    // Double — floating point holds commutativity/identity ONLY for finite
    // inputs, and is NOT associative even for finite values → witnesses NO
    // protocol (it is not a Monoid). Listed explicitly so its special-case
    // status is visible rather than read as an oversight.
    private static let doubleLaws: [KnownProperty] = [
        law(
            "Double", "commutative under + (finite inputs)", "a + b == b + a",
            "let a = randDouble(), b = randDouble(); return a + b == b + a",
            note: "Finite inputs only. NOT a Monoid — `+` is not associative (see caveats)."
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

    // Bool — && / || are bounded semilattices (over boolean values)
    private static let boolLaws: [KnownProperty] = [
        law(
            "Bool", "semilattice under &&", "(a && b) == (b && a)",
            "let a = randBool(), b = randBool(); return (a && b) == (b && a)",
            witnesses: "Semilattice"
        ),
        law(
            "Bool", "semilattice under ||", "((a || b) || c) == (a || (b || c))",
            "let a = randBool(), b = randBool(), c = randBool(); return ((a || b) || c) == (a || (b || c))",
            witnesses: "Semilattice"
        ),
        law(
            "Bool", "idempotent under &&", "(a && a) == a",
            "let a = randBool(); return (a && a) == a",
            witnesses: "Semilattice"
        )
    ]

    // String — free monoid under concatenation (NOT commutative), plus
    // uppercasing idempotence and the reverse involution.
    private static let stringLaws: [KnownProperty] = [
        law(
            "String", "monoid under + (NOT commutative)", "(a + b) + c == a + (b + c)",
            "let a = randStr(), b = randStr(), c = randStr(); return (a + b) + c == a + (b + c)",
            witnesses: "Monoid", template: "associativity"
        ),
        law(
            "String", "concatenation identity", "a + \"\" == a",
            "let a = randStr(); return a + \"\" == a",
            witnesses: "Monoid"
        ),
        law(
            "String", "idempotent under uppercasing", "s.uppercased().uppercased() == s.uppercased()",
            "let s = randStr(); return s.uppercased().uppercased() == s.uppercased()"
        ),
        law(
            "String", "reverse is an involution",
            "String(String(s.reversed()).reversed()) == s",
            "let s = randStr(); return String(String(s.reversed()).reversed()) == s"
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
            "let a = randArr(), b = randArr(), c = randArr(); return (a + b) + c == a + (b + c)",
            witnesses: "Monoid", template: "associativity"
        )
    ]

    // Set — bounded semilattice under union / intersection
    private static let setLaws: [KnownProperty] = [
        law(
            "Set", "semilattice under union", "a.union(b) == b.union(a)",
            "let a = randSet(), b = randSet(); return a.union(b) == b.union(a)",
            witnesses: "Semilattice", template: "commutativity"
        ),
        law(
            "Set", "semilattice under union", "a.union(b).union(c) == a.union(b.union(c))",
            "let a = randSet(), b = randSet(), c = randSet(); return a.union(b).union(c) == a.union(b.union(c))",
            witnesses: "Semilattice"
        ),
        law(
            "Set", "idempotent under union", "a.union(a) == a",
            "let a = randSet(); return a.union(a) == a",
            witnesses: "Semilattice"
        ),
        law(
            "Set", "semilattice under intersection", "a.intersection(b) == b.intersection(a)",
            "let a = randSet(), b = randSet(); return a.intersection(b) == b.intersection(a)",
            witnesses: "Semilattice"
        ),
        // Collections/async workplan Phase 1 M4 — stdlib analogs of the
        // kit's SetAlgebra Boolean-algebra completion (SwiftPropertyLaws
        // v3.12.0: distributivity / absorption / relative De Morgan), so
        // the catalog stays in lockstep with what the kit can check.
        law(
            "Set", "distributive lattice",
            "a.union(b.intersection(c)) == a.union(b).intersection(a.union(c))",
            "let a = randSet(), b = randSet(), c = randSet(); "
                + "return a.union(b.intersection(c)) == a.union(b).intersection(a.union(c))",
            witnesses: "SetAlgebra"
        ),
        law(
            "Set", "absorption", "a.union(a.intersection(b)) == a",
            "let a = randSet(), b = randSet(); return a.union(a.intersection(b)) == a",
            witnesses: "SetAlgebra"
        ),
        law(
            "Set", "De Morgan (relative form)",
            "a.subtracting(b.union(c)) == a.subtracting(b).intersection(a.subtracting(c))",
            "let a = randSet(), b = randSet(), c = randSet(); "
                + "return a.subtracting(b.union(c)) == a.subtracting(b).intersection(a.subtracting(c))",
            witnesses: "SetAlgebra",
            note: "Stated against a minuend — SetAlgebra has no complement. A subtracting "
                + "implemented as symmetricDifference passes every other Set law here; "
                + "only this shape catches it (kit: SetAlgebra.deMorganForUnion)."
        ),
        // Symmetric difference is a commutative group (identity ∅, self-inverse).
        // The kit models no such protocol (CommutativeGroup is deferred), so these
        // tag no witness — the truths are stated and verified directly.
        law(
            "Set", "commutative under symmetricDifference",
            "a.symmetricDifference(b) == b.symmetricDifference(a)",
            "let a = randSet(), b = randSet(); "
                + "return a.symmetricDifference(b) == b.symmetricDifference(a)",
            template: "commutativity"
        ),
        law(
            "Set", "symmetricDifference self-inverse",
            "a.symmetricDifference(b).symmetricDifference(b) == a",
            "let a = randSet(), b = randSet(); "
                + "return a.symmetricDifference(b).symmetricDifference(b) == a"
        )
    ]

    // Caveats — plausible-looking NON-properties (never asserted true)
    private static let caveatEntries: [KnownProperty] = [
        caveat(
            "String", "+ is NOT commutative",
            "`a + b != b + a` in general — concatenation is ordered.",
            template: "commutativity"
        ),
        caveat(
            "Array", "+ is NOT commutative",
            "`a + b != b + a` in general — concatenation is ordered.",
            template: "commutativity"
        ),
        caveat(
            "Double", "+ is NOT associative",
            "IEEE-754 rounding: `(a + b) + c != a + (b + c)` for some values.",
            template: "associativity"
        ),
        caveat(
            "Set", "subtracting is NOT commutative",
            "`a.subtracting(b) != b.subtracting(a)` in general.",
            template: "commutativity"
        ),
        caveat(
            "Dictionary", "merging is NOT commutative on key collisions",
            "`d1.merging(d2) { a, _ in a } != d2.merging(d1) { a, _ in a }` when a key is in "
                + "both with different values — the uniquing closure's `first` argument differs.",
            template: "commutativity"
        ),
        caveat(
            "Bool", "&& / || short-circuit — laws hold for VALUES, not evaluation",
            "Swift does not evaluate the right operand when the left decides the result, "
                + "so with side effects `a && f()` and `f() && a` differ in what runs."
        )
    ]

    public static let all: [KnownProperty] =
        intLaws + doubleLaws + boolLaws + stringLaws + arrayLaws + setLaws
            + optionalLaws + dictionaryLaws + stackLaws + queueLaws + caveatEntries
}
