/// V1.24.B — curated set of canonical Swift mutating-method names whose
/// lifted shadows are NOT idempotent. Direct cycle-20 finding closure
/// (V1.20.C 4/4 reject on OC `reverse()`, `removeFirst()`, `removeLast()`,
/// `OrderedSet.reverse()` lifted-idempotence picks).
///
/// **Why these specific names:**
/// - `reverse`: `reverse(reverse(s)) = s ≠ reverse(s)` for non-palindromes.
/// - `removeFirst` / `removeLast`: state advances per call (removes one
///   element); not idempotent.
/// - `pop` / `popFirst` / `popLast`: same shape as remove*; pop-shaped APIs
///   that modify state-and-return. Bare `pop` is the canonical stack / queue
///   / heap consume — it removes (and returns) the top element, so `pop(pop(s))`
///   removes two elements ≠ `pop(s)`. (Dogfood finding: real
///   `PriorityQueue.pop()` lifted-idempotence picks surfaced at Likely on
///   `apple/swift-nio`; the `popFirst`/`popLast` siblings were already curated
///   but the bare `pop()` slipped through the exact-name match.)
/// - `dropFirst` / `dropLast`: same shape; "drop" verb is a synonym for
///   "remove" in this context.
/// - `negate` / `toggle` / `invert` / `complement` / `twosComplement`:
///   canonical **involutions** — `f(f(s)) = s ≠ f(s)` (the same structural
///   argument as `reverse`, which already inverts ordering). A self-inverse
///   mutator is non-idempotent for every value `s` where `f(s) ≠ s`.
///   (Dogfood finding: real `BigInt.negate()` + `Array.twosComplement()`
///   lifted-idempotence picks surfaced at Likely on `attaswift/BigInt`;
///   `Bool.toggle()` is the canonical stdlib case.)
///
/// **Distinct from V1.21.A's `iteratorMethodNames`.** V1.21.A's
/// `next` / `advance` / `nextState` / `step` / `findNext` /
/// `advanceToNextUnoccupiedBucket` curated set requires the carrier to
/// conform to `IteratorProtocol` (or have an Iterator-suffix name) —
/// V1.21.A's joint match (curated method + Iterator-shape carrier) limits
/// false-positive surface. V1.24.B's curated set fires on **any value-
/// semantic carrier** (no protocol-conformance requirement) because the
/// canonical Swift naming convention `mutating func reverse()` is by-
/// design non-idempotent regardless of carrier identity.
///
/// Mechanism class: extension of class 7's carrier-protocol-conformance
/// veto sub-class (V1.21.A lineage) — generalizes from "Iterator-method-
/// name on Iterator-conforming carrier" to "explicit-non-idempotent-
/// mutator-name on any value-semantic carrier."
public enum MutatorBlockedFromIdempotence {

    /// Canonical Swift mutating-method names that are non-idempotent
    /// by structural construction (NOT by carrier-protocol contract).
    ///
    /// Project-vocabulary extension via the existing `Vocabulary.idempotenceVerbs`
    /// slot — project-specific non-idempotent mutator names belong
    /// alongside the project's idempotence verb list (those identify
    /// IDEMPOTENT names; this curated set identifies non-idempotent
    /// names by structural argument).
    public static let curated: Set<String> = [
        "reverse",
        "removeFirst",
        "removeLast",
        "pop",
        "popFirst",
        "popLast",
        "dropFirst",
        "dropLast",
        // Involutions — self-inverse mutators (`f(f(s)) == s ≠ f(s)`),
        // the same structural non-idempotence as `reverse`.
        "negate",
        "toggle",
        "invert",
        "complement",
        "twosComplement"
    ]

    /// Name *prefixes* for the consuming-iterator family — a `mutating`
    /// method that **pops or gets the next** element advances/removes state,
    /// so its lifted shadow is never idempotent (`f(f(s)) ≠ f(s)`), exactly
    /// like the exact-name `popFirst`/`removeFirst`. Prefix (not exact)
    /// because the suffix varies per call site (`popNext`, `popNextValue`,
    /// `popNextElementIfValue`, `popNextHexByte`, `getNext`, …) — "pop/get
    /// the next X" is unambiguously consuming for every X, so no idempotent
    /// counterexample exists. (Dogfood findings: `apple/swift-nio`
    /// `popNextHexByte()`; `apple/swift-argument-parser` `popNext()` /
    /// `popNextValue()` / `popNextElementIfValue()` (body calls
    /// `removeFirst()`) + `ArrayWrapper.getNext()` (body does
    /// `currentIndex += 1`) — all surfaced at Likely across two independent
    /// libraries, so the family is generalizable, not a one-off name.)
    public static let consumePrefixes: Set<String> = [
        "popNext",
        "getNext"
    ]

    /// Involution verb *prefixes* — a `mutating` method that **toggles /
    /// negates / inverts / complements** something is a self-inverse
    /// (`f(f(s)) == s ≠ f(s)`), so its lifted shadow is never idempotent,
    /// exactly like the bare `toggle` / `negate` in `curated`. Prefix (not
    /// exact) because the object is usually named in the suffix (`toggleAll`,
    /// `invertColors`, `negatePolarity`, `complementAll`) — "toggle / negate /
    /// invert / complement X" is a self-inverse for every X, so no idempotent
    /// counterexample exists. (Backtest finding: swift-collections
    /// `BitArray.toggleAll()` surfaced lifted-idempotence at Likely 45 — the
    /// bare `toggle` was curated, but the `toggleAll` compound slipped the
    /// exact-name match, the same gap the `pop` → `popNext*` prefix fix
    /// closed.)
    public static let involutionPrefixes: Set<String> = [
        "toggle",
        "negate",
        "invert",
        "complement"
    ]

    /// `true` when `name` is a non-idempotent mutator — an exact `curated`
    /// name, a `consumePrefixes` member, or an `involutionPrefixes` member.
    public static func isBlocked(_ name: String) -> Bool {
        curated.contains(name)
            || consumePrefixes.contains { name.hasPrefix($0) }
            || involutionPrefixes.contains { name.hasPrefix($0) }
    }
}
