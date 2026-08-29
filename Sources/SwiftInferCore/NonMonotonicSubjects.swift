import Foundation

/// Subjects for which `monotonicity` is **definitionally false** — a hash, or a
/// mathematical function that is not order-preserving.
///
/// `monotonicity` fires on a `Comparable -> Comparable` signature and nothing asks whether
/// the operation plausibly HAS the property (`open-threads.md` row 69). This closes the
/// half of that where the answer is knowable from the name alone.
///
/// ## The set is "not monotonic", NOT "trigonometric", and the difference is the point
///
/// `MathForwardFunctions.curated` already lists the elementary functions and **cannot be
/// reused here**: it contains `exp`, `log`, `log2`, `log10`, `sqrt` and `cbrt`, every one of
/// which IS monotonic and correctly proposed. Reusing it would remove true laws to remove
/// false ones.
///
/// The same cut runs through the trigonometric family itself:
///
/// | function | monotonic? | in this set |
/// |---|---|---|
/// | `sin`, `cos`, `tan` | no — periodic | **yes** |
/// | `cosh` | no — even, decreasing then increasing | **yes** |
/// | `acos` | no — *decreasing*, and the template checks non-decreasing | **yes** |
/// | `sinh`, `tanh`, `asin`, `atan`, `asinh`, `atanh`, `acosh` | **yes** — strictly increasing | no |
///
/// **Measured on the 20 manifest corpora** (`monotonicity-subject-census.md`), the only
/// trigonometric rows are `_cos(_:)` and `_sin(_:)`, twice each — so the narrow set catches
/// every measured row and the wide one would have been a liability with no compensating
/// gain. That the wide set costs nothing *today* is not a reason to ship it.
///
/// ## Hashes
///
/// A hash that preserves order is a broken hash — the property is the negation of what the
/// function is for. Matched on the token `hash`, which reaches the stdlib's `_rawHashValue`
/// and `_hashValue` spellings as well as `hashValue` itself.
///
/// ## Why tokens, and not the two simpler probes
///
/// Both simpler forms were measured wrong, in one run, on this exact population:
///
/// - **whole-name equality** reads 0 trigonometric and 4 hash — it misses `_cos`,
///   `_rawHashValue` and `_hashValue`, because the stdlib spells its internals with a
///   leading underscore and a prefix.
/// - **substring** reads 17 trigonometric and every one is a coincidence:
///   `dis`*`tan`*`ce(to:)`, `editDistance(to:)`, `second`*`sIn`*`Day`,
///   `numWeek`*`sIn`*`Year`, `clampedMinimumDay`*`sIn`*`FirstWeek`.
///
/// `distance` contains `tan`; `secondsInDay` contains `sin`. Splitting on `_` and camelCase
/// boundaries and testing membership is what a reader means by *is this function a hash*.
public enum NonMonotonicSubjects {

    /// Mathematical functions that are **not** order-preserving. Deliberately narrower than
    /// `MathForwardFunctions.curated` — see the table above.
    public static let nonMonotonicMathNames: Set<String> = [
        "sin", "cos", "tan", "cosh", "acos"
    ]

    /// The token that identifies a hash function.
    public static let hashToken = "hash"

    /// Lowercased tokens of a declaration name, split on `_` and camelCase boundaries.
    /// `_rawHashValue(seed:)` → `["raw", "hash", "value"]`.
    ///
    /// Argument labels are dropped first: the label is the CALLER's word, not the
    /// function's, and `wordCount(forScale:)` must not tokenise to include `scale`.
    public static func tokens(of displayName: String) -> Set<String> {
        let bare = String(displayName.prefix { $0 != "(" })
        var collected: [String] = []
        var current = ""
        for character in bare {
            if character == "_" {
                if !current.isEmpty { collected.append(current); current = "" }
            } else if character.isUppercase {
                if !current.isEmpty { collected.append(current) }
                current = String(character)
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { collected.append(current) }
        return Set(collected.map { $0.lowercased() })
    }

    /// `true` when `monotonicity` cannot hold for this subject on the strength of its name.
    public static func isDefinitionallyNonMonotonic(_ displayName: String) -> Bool {
        let names = tokens(of: displayName)
        if names.contains(hashToken) { return true }
        return !names.isDisjoint(with: nonMonotonicMathNames)
    }
}
