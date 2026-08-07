import SwiftInferCore

/// The curated inverse-name vocabulary `RoundTripTemplate` scores against, and
/// the one sub-family of it that owes a disclosure.
///
/// Split out of `RoundTripTemplate.swift` when the §3a widening pushed that
/// file past the 400-line cap. Vocabulary and scoring are separable concerns
/// anyway: this file is the list of names the catalog knows, and nothing else.
extension RoundTripTemplate {

    /// Curated inverse-name pairs per PRD §5.2. Project-vocabulary
    /// extension (§4.5's `inversePairs` from `vocabulary.json`) lands at
    /// M2; M1.4 ships the curated list, exact-match in either order.
    ///
    /// Shared with `InversePairTemplate` (at weight 10 there rather than 40),
    /// so an addition here widens both templates.
    ///
    /// **The text↔structure block is the `docs/measurements/parsing-catalog-gap.md` §3a
    /// closure.** Before it, the list held exactly one parse-ish entry —
    /// `parse`/`format` — and every other spelling of the same law scored 35,
    /// which is `Possible`, which is hidden on a default run. Measured on
    /// identical type shapes: `parse`/`format` → 75 `Strong`; `parse`/`print`
    /// and `parse`/`render` → 35, invisible. That is the `intersect` /
    /// `intersection` stale-stem failure of Appendix C in a new place — the
    /// dictionary is missing the word, so the tool never checks it, and the
    /// silence reads as a clean bill of health.
    public static let curatedInversePairs: [(String, String)] = [
        // Codec — a value and its wire form.
        ("encode", "decode"),
        ("serialize", "deserialize"),
        ("compress", "decompress"),
        ("encrypt", "decrypt"),
        ("marshal", "unmarshal"),
        ("pack", "unpack"),

        // Text ↔ structure — the parser's law, under every name it is
        // actually written with. `parse`/`format` was already here and the
        // rest are the same claim: text in, tree out, tree back to text.
        //
        // `parse`/`description` is included for completeness and reaches
        // less than it looks like it does: Swift's idiomatic printer is
        // `var description: String` on a `CustomStringConvertible`
        // conformance, and pairing against a *computed property* is a
        // separate gap (§3c) that this list cannot close. A hand-written
        // `func description() -> String` is what matches here.
        ("parse", "format"),
        ("parse", "print"),
        ("parse", "unparse"),
        ("parse", "render"),
        ("parse", "description"),
        ("tokenize", "join"),

        // Persistence — same shape, but the round trip runs through a STORE
        // rather than through a pure function, so the law is conditional on
        // that store. See `persistenceInverseVerbs` and the caveat it drives.
        ("read", "write"),
        ("load", "save"),

        // Stateful pairs — not `g(f(t)) == t` over values at all; kept from
        // the original M1.4 list, where the claim is about the state a pair
        // of operations leaves behind.
        ("push", "pop"),
        ("insert", "remove"),
        ("open", "close"),
        ("lock", "unlock")
    ]

    /// The verbs whose round trip runs through a **store** — a file, a
    /// database, a keychain — rather than through a pure function.
    ///
    /// `write(x)` then `read()` is a real and valuable law, but it is only
    /// true of an *injected, deterministic* store: against a live filesystem
    /// it depends on a path that may not exist, permissions, a concurrent
    /// writer, and an encoding the reader has to agree with. The pair is
    /// worth surfacing — this is exactly the shape a fake-backed property
    /// catches bugs in — but a reader handed a `Strong` claim with no note
    /// would reasonably read it as "this holds", and against real I/O it does
    /// not. So the pair scores like the others and carries its condition in
    /// `makeCaveats`.
    static let persistenceInverseVerbs: Set<String> = [
        "read", "write", "load", "save"
    ]
}
