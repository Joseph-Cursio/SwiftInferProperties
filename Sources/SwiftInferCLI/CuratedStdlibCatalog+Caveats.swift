import Foundation

/// The **caveat** half of `CuratedStdlibCatalog` — plausible-looking NON-properties,
/// documented and never asserted true. `StdlibAnchor` turns a matching caveat into a
/// "why this might be wrong" line on a discovered candidate.
///
/// Its own file because it crossed the 400-line cap in the primary one, and because it is
/// the half that grew when the catalog's "algebraic" scope restriction was lifted: the six
/// original entries are all algebraic, which is what that restriction produced — a catalog
/// that could only warn about laws it could also state.
extension CuratedStdlibCatalog {

    // Caveats — plausible-looking NON-properties (never asserted true)
    // Internal rather than `private`: it moved out of `CuratedStdlibCatalog.swift` and its
    // one consumer (the `all` aggregate) stayed behind.
    static let caveatEntries: [CuratedEntry] = [
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
        ),

        // Non-algebraic traps. The six above are all algebraic, which is what the
        // now-removed "algebraic" scope restriction produced: the catalog could only warn
        // about laws it could also state. Each entry below is quoted from the stdlib's own
        // documentation rather than recalled — see the note text for the source.
        caveat(
            "Sequence", "iterating TWICE is not guaranteed to re-yield",
            "Sequence.swift's own \"Repeated Access\" section: \"The `Sequence` protocol "
                + "makes no requirement on conforming types regarding whether they will be "
                + "destructively consumed by iteration ... don't assume that multiple "
                + "`for`-`in` loops on a sequence will either resume iteration or restart "
                + "from the beginning.\" So `f(s) == f(s)` can be FALSE for a correct "
                + "single-pass sequence — the determinism law does not hold on the carrier, "
                + "and this is the trap `IdempotenceTemplate`'s stream-consumption veto "
                + "exists for.",
            template: "idempotence"
        ),
        caveat(
            "Set", "iteration order is not a property — do not round-trip through Array",
            "Set.swift: \"Because a set is not an ordered collection, the 'first' element "
                + "may not...\". `Array(Set(xs))` is not `xs`, and its order is not stable "
                + "across processes — Swift seeds hashing per launch. A round-trip through "
                + "an ordered carrier is a false law that passes locally and fails in CI.",
            template: "round-trip"
        ),
        caveat(
            "Dictionary", "iteration order is not a property",
            "Dictionary.swift:316: \"Every dictionary is an unordered collection of "
                + "key-value pairs.\" Same trap as `Set` — any law comparing iteration "
                + "order, or round-tripping through an ordered carrier, is false while "
                + "usually appearing to pass.",
            template: "round-trip"
        )
    ]

    // NOT added, and recorded so it is not re-proposed: "`sort()` is not stable". That was
    // true of Swift once and is false now — `Sort.swift:40` states "The sorting algorithm is
    // guaranteed to be stable." It was nearly added here from recollection, which is exactly
    // the failure mode a *curated* catalog is most exposed to: every entry is someone's
    // memory until it is checked against the source.
}
