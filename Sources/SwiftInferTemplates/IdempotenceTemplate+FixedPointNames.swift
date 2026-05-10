import SwiftInferCore

/// V1.22.C — fixed-point-name positive signal extension on
/// `IdempotenceTemplate`. **First recall-positive signal in the
/// post-V1.4.3 era** — all prior cycles (V1.4.3 onward) shipped
/// suppression-only mechanisms; V1.22.C introduces a positive signal
/// class (mechanism class 14 in the cycle-19 taxonomy).
///
/// Fires `+10` weight when `summary.name ∈ FixedPointNames.curated`.
/// Score impact:
///
/// - Bare typeSymmetry (+30) + carrier (+5) + fixed-point (+10) = +45
///   → Likely (was Possible at +35 without this signal).
/// - typeSymmetry (+30) + curated verb (+40, V1.4.1) + carrier (+5) +
///   fixed-point (+10) = +85 → Strong. (Doesn't apply on the v1.22
///   FixedPointNames set, which excludes V1.4.1 curatedVerbs overlap.)
///
/// Wired into `IdempotenceTemplate.suggest(for:)` alongside the existing
/// `nameSignal(for:vocabulary:)` (V1.4.1 curated-verb at +40). Both
/// signals can fire on the same call (different curated sets), giving
/// cumulative recall-positive movement on names that appear in both.
///
/// **Lifted-path coverage.** V1.19.B's lifted IdempotenceTemplate path
/// already covers fixed-point names via the curated-verb signal (lifted
/// path uses `IdempotenceTemplate.curatedVerbs` directly). V1.22.C only
/// fires on the **non-lifted** path — the gap that motivated this
/// workstream is non-lifted-only.
extension IdempotenceTemplate {

    /// Returns a `+10` recall-positive signal when `summary.name` is in
    /// `FixedPointNames.curated`. `nil` otherwise.
    static func fixedPointNameSignal(for summary: FunctionSummary) -> Signal? {
        guard FixedPointNames.curated.contains(summary.name) else {
            return nil
        }
        return Signal(
            kind: .fixedPointName,
            weight: 10,
            detail: "Fixed-point name '\(summary.name)' — function name signals "
                + "canonical-form transform whose application is idempotent "
                + "(lower-confidence than V1.4.1 curated-verb list; +10 vs +40)"
        )
    }
}
