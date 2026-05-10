/// V1.21.C — curated set of math-library forward-function names + the
/// canonical-inverse-pair allowlist. Three-cycle carry-forward priority
/// (cycles 15/16/17) addressing the dominant CM elementary-functions
/// noise class in non-lifted idempotence + non-lifted round-trip.
///
/// **Cycle-17 measurement justifies this.** The V1.20.C 46-decision
/// triage measured `exp` / `log` / `sqrt` non-lifted idempotence at
/// 0/3 = 0% (picks #18, #19, #20 all reject — `exp(exp(z)) ≠ exp(z)`,
/// `log(log(z)) ≠ log(z)`, `sqrt(sqrt(z)) = z^(1/4) ≠ z^(1/2)` except
/// at fixed points). The full v1.19 surface has 17 of 25 (68%) CM
/// non-lifted idempotence candidates in this class; the round-trip
/// surface has ~129 of 136 (~95%) CM round-trip candidates as cross-
/// product noise (forward-forward like `exp × cosh`, `log × sqrt`).
///
/// Two consumer paths:
///
/// 1. **Idempotence non-lifted** — `IdempotenceTemplate.mathForwardFunctionVeto(for:)`
///    fires veto when `summary.name ∈ curated` AND signature is `(T) -> T`.
///    By-construction precision: math-library forward functions are not
///    idempotent (the only fixed points are isolated values, not the
///    full input domain).
///
/// 2. **Round-trip non-lifted** — `RoundTripTemplate.mathForwardFunctionPairVeto(for:)`
///    fires veto when **both** pair sides have `name ∈ curated` AND `(T) -> T`
///    shape, **EXCEPT** when the pair appears in `canonicalInversePairs`
///    (orientation-insensitive). Preserves the 7 cycle-17 canonical-
///    inverse anchors (`exp × log`, `cos × acos`, `sin × asin`, `tan × atan`,
///    `cosh × acosh`, `sinh × asinh`, `tanh × atanh`) which all measured
///    accept; suppresses the cross-product noise.
///
/// Mechanism class: extension of class 7 (function-name + type-shape
/// composite, V1.14.1 / V1.16.1 lineage). Veto magnitude `-25` uniform
/// with V1.14.1 / V1.16.1 SetAlgebra-shape veto.
public enum MathForwardFunctions {

    /// Curated math-library forward-function names. Includes stdlib
    /// `Foundation` math families + swift-numerics extensions
    /// (`expMinusOne`, `log1p` / `log(onePlus:)`, `hypot`, `atan2`).
    /// Per the v1.21 plan §"Open decisions" #3 lean: include the
    /// numerics-extended set so the cycle-17 CM cross-product noise
    /// involving `expMinusOne` and `log(onePlus:)` is also closed.
    ///
    /// Excludes `pow` (always two-arg shape — out of `(T) -> T` scope)
    /// and `abs` / `negate` (idempotent on real inputs — `abs(abs(x)) =
    /// abs(x)` so they should NOT be vetoed; future-cycle review may
    /// promote these to a separate `IdempotentMathFunctions` allowlist).
    public static let curated: Set<String> = [
        // Exponential family
        "exp", "exp2", "expMinusOne",
        // Logarithm family
        "log", "log2", "log10", "log1p", "onePlus",
        // Trigonometric forward
        "sin", "cos", "tan",
        // Inverse trigonometric (asin(asin(z)) ≠ asin(z) — also forward
        // in the idempotence sense; round-trip pairs them with their
        // forward via canonicalInversePairs)
        "asin", "acos", "atan", "atan2",
        // Hyperbolic
        "sinh", "cosh", "tanh",
        // Inverse hyperbolic
        "asinh", "acosh", "atanh",
        // Roots
        "sqrt", "cbrt",
        // Misc
        "hypot"
    ]

    /// Canonical forward-inverse pairs that the round-trip veto **does not**
    /// suppress. Each entry is `(forward, inverse)` in canonical
    /// orientation; orientation-insensitive matching at the call site
    /// preserves both `(exp, log)` and `(log, exp)` round-trip claims.
    ///
    /// **Cycle-17 measurement basis.** The 7 entries here correspond to
    /// the 7 V1.20.C cycle-17 picks that all measured accept (#5–#11):
    /// `exp × log`, `cosh × acosh`, `sinh × asinh`, `tanh × atanh`,
    /// `cos × acos`, `sin × asin`, `tan × atan`.
    ///
    /// Note: `(sqrt, /)` and `(cbrt, /)` are NOT here — root functions
    /// don't have a curated forward-inverse counterpart in the elementary-
    /// functions library (the inverse of `sqrt` is the squaring operation,
    /// which is also forward; round-trip on `sqrt` would only hold within
    /// a non-negative subdomain, which the rubric excludes per the
    /// "asymmetric postconditions" criterion).
    ///
    /// `(log1p, expMinusOne)` IS included — `log1p(expMinusOne(z)) = z`
    /// on the small-magnitude subdomain where both numerical variants
    /// are accurate; this is the by-design accurate-near-zero pair the
    /// numerics library exposes for `log(1+x)` ↔ `exp(x) - 1`.
    public static let canonicalInversePairs: [(forward: String, inverse: String)] = [
        ("exp", "log"),
        ("exp2", "log2"),
        ("expMinusOne", "log1p"),
        ("expMinusOne", "onePlus"),
        ("sin", "asin"),
        ("cos", "acos"),
        ("tan", "atan"),
        ("sinh", "asinh"),
        ("cosh", "acosh"),
        ("tanh", "atanh")
    ]

    /// Returns `true` when `(name1, name2)` matches a `canonicalInversePairs`
    /// entry in either orientation. Used by `RoundTripTemplate.mathForwardFunctionPairVeto`
    /// to preserve the canonical-inverse anchor pairs while suppressing
    /// cross-product noise.
    public static func isCanonicalInversePair(_ name1: String, _ name2: String) -> Bool {
        canonicalInversePairs.contains {
            ($0.forward == name1 && $0.inverse == name2)
                || ($0.forward == name2 && $0.inverse == name1)
        }
    }
}
