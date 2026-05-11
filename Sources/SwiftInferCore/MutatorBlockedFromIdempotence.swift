/// V1.24.B — curated set of canonical Swift mutating-method names whose
/// lifted shadows are NOT idempotent. Direct cycle-20 finding closure
/// (V1.20.C 4/4 reject on OC `reverse()`, `removeFirst()`, `removeLast()`,
/// `OrderedSet.reverse()` lifted-idempotence picks).
///
/// **Why these specific names:**
/// - `reverse`: `reverse(reverse(s)) = s ≠ reverse(s)` for non-palindromes.
/// - `removeFirst` / `removeLast`: state advances per call (removes one
///   element); not idempotent.
/// - `popFirst` / `popLast`: same shape as remove*; pop-shaped APIs that
///   modify state-and-return.
/// - `dropFirst` / `dropLast`: same shape; "drop" verb is a synonym for
///   "remove" in this context.
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
        "popFirst",
        "popLast",
        "dropFirst",
        "dropLast"
    ]
}
