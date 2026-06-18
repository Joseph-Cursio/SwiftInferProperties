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
}
