import SwiftInferCore

/// V1.21.C — math-library forward-function veto on non-lifted
/// idempotence. Three-cycle carry-forward (cycles 15/16/17) closed by
/// the cycle-17 measurement: `exp` / `log` / `sqrt` non-lifted
/// idempotence at 0/3 = 0% (V1.20.C picks #18, #19, #20 all reject).
///
/// Fires veto (weight `Signal.vetoWeight`, kind `.protocolCoveredProperty`
/// — reuses the existing veto signal kind per V1.14.1 / V1.16.1
/// precedent rather than introducing a new kind for a single-cycle
/// extension) when:
///
///   - `summary.name ∈ MathForwardFunctions.curated`, AND
///   - signature is `(T) -> T` (single param, return type matches param
///     type; same shape gate as `IdempotenceTemplate.typeSymmetrySignal`).
///
/// Mechanism class: extension of class 7 (function-name + type-shape
/// composite). Same scoring posture as V1.14.1 SetAlgebra-shape veto:
/// full veto collapses score to Suppressed (filtered from
/// `--include-possible`).
///
/// Magnitude estimate (cycle-19 projection): closes ~17 CM elementary-
/// functions non-lifted idempotence picks (the dominant noise class in
/// the v1.19 25-candidate non-lifted idempotence pool).
extension IdempotenceTemplate {

    /// Returns a veto `Signal` when `summary` is a single-param
    /// `(T) -> T` function whose name is in `MathForwardFunctions.curated`.
    /// `nil` otherwise.
    ///
    /// Wired into `IdempotenceTemplate.suggest(for:)` alongside the
    /// existing `setAlgebraShapeVeto`, `protocolCoverageVeto`,
    /// `nonDeterministicVeto` calls.
    static func mathForwardFunctionVeto(for summary: FunctionSummary) -> Signal? {
        guard MathForwardFunctions.curated.contains(summary.name) else {
            return nil
        }
        // Same shape gate as `typeSymmetrySignal` — re-checked here so
        // the veto is robust to call-site re-ordering.
        guard summary.parameters.count == 1,
              let param = summary.parameters.first,
              !param.isInout,
              !summary.isMutating,
              let returnType = summary.returnTypeText,
              returnType == param.typeText,
              returnType != "Void",
              returnType != "()" else {
            return nil
        }
        return Signal(
            kind: .protocolCoveredProperty,
            weight: Signal.vetoWeight,
            detail: "Math-forward function '\(summary.name)' on (T) -> T shape — "
                + "`\(summary.name)(\(summary.name)(z))` is not idempotent (e.g., "
                + "exp(exp(z)) = e^(e^z) ≠ exp(z); the only fixed points of "
                + "elementary forward functions are isolated values, not the "
                + "input domain)"
        )
    }
}
