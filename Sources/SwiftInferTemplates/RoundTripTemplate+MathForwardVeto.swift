import SwiftInferCore

/// V1.21.C — math-library forward-function pair veto on non-lifted
/// round-trip. Suppresses CM elementary-functions cross-product noise
/// (forward × forward like `exp × cosh`, `log × sqrt`) while preserving
/// the canonical inverse-pair anchors (`exp × log`, `cos × acos`, etc.)
/// that the cycle-17 V1.20.C triage measured at 7/7 = 100% accept.
///
/// Fires veto (weight `Signal.vetoWeight`, kind `.protocolCoveredProperty`)
/// when:
///
///   - **Both** pair sides have `name ∈ MathForwardFunctions.curated`, AND
///   - both have `(T) -> T` shape (single param, same return type),
///   - AND the pair is **not** in `MathForwardFunctions.canonicalInversePairs`
///     (orientation-insensitive match).
///
/// The orientation-insensitive allowlist preserves both `(exp, log)` and
/// `(log, exp)` round-trip claims; mirrors V1.18.C `DualStylePairing`'s
/// orientation-insensitive matching.
///
/// Mechanism class: extension of class 7 (function-name + type-shape
/// composite). Parallels V1.16.1's third-template extension pattern
/// (V1.14.1 inverse-pair → V1.16.1 idempotence + round-trip → V1.21.C
/// idempotence + round-trip math-forward variant).
///
/// Magnitude estimate (cycle-19 projection): closes ~129 of 136 CM
/// round-trip cross-product picks; preserves the 7 canonical-inverse
/// anchors. The largest single mechanism in v1.21.
extension RoundTripTemplate {

    /// Returns a veto `Signal` when both pair sides match the math-forward
    /// shape AND the pair is not a canonical inverse. `nil` otherwise.
    ///
    /// Wired into `RoundTripTemplate.suggest(for:)` alongside the existing
    /// `setAlgebraShapeVeto`, `protocolCoverageVeto`, `nonDeterministicVeto`
    /// calls.
    static func mathForwardFunctionPairVeto(for pair: FunctionPair) -> Signal? {
        let forward = pair.forward
        let reverse = pair.reverse
        // Both names must be in the curated math-forward set.
        guard MathForwardFunctions.curated.contains(forward.name),
              MathForwardFunctions.curated.contains(reverse.name) else {
            return nil
        }
        // Both must be (T) -> T shape (single non-inout param, return
        // type matches param type, not Void). Same gate posture as
        // `IdempotenceTemplate.mathForwardFunctionVeto`.
        guard isSingleParamTToT(forward), isSingleParamTToT(reverse) else {
            return nil
        }
        // Allowlist: orientation-insensitive canonical-inverse-pair check.
        // Preserves `(exp, log)` / `(log, exp)` / `(sin, asin)` etc.
        if MathForwardFunctions.isCanonicalInversePair(forward.name, reverse.name) {
            return nil
        }
        return Signal(
            kind: .protocolCoveredProperty,
            weight: Signal.vetoWeight,
            detail: "Math-forward cross-product '\(forward.name) × \(reverse.name)' — "
                + "not in canonical inverse-pair allowlist "
                + "(`{(exp, log), (sin, asin), (cos, acos), (tan, atan), "
                + "(sinh, asinh), (cosh, acosh), (tanh, atanh), ...}`); "
                + "both are forward elementary functions, not inverses"
        )
    }

    /// Single-param `(T) -> T` shape gate — same predicates as
    /// `IdempotenceTemplate.typeSymmetrySignal`'s positive case, scoped
    /// to round-trip's per-half check. Lifted to a helper so both
    /// `mathForwardFunctionPairVeto` halves apply the gate identically.
    private static func isSingleParamTToT(_ summary: FunctionSummary) -> Bool {
        guard summary.parameters.count == 1,
              let param = summary.parameters.first,
              !param.isInout,
              !summary.isMutating,
              let returnType = summary.returnTypeText,
              returnType == param.typeText,
              returnType != "Void",
              returnType != "()" else {
            return false
        }
        return true
    }
}
