import SwiftInferCore

/// V1.24.D — capacity-from-scale + formatter shape-disambiguation veto
/// on `IdempotenceTemplate.suggest(for:)` non-lifted path. Direct cycle-20
/// finding closure (the 5-cycle-flat 0% idempotence non-lifted rate is
/// dominated by shape-coincidence patterns where the function's
/// signature matches `(T) -> T` but the semantic content is NOT
/// idempotent).
///
/// Two shape-coincidence classes vetoed:
///
/// 1. **Capacity-from-scale shape.** Function name matches `*Capacity*`
///    or `*Count*` AND first-parameter label is `forScale:` or
///    `forCapacity:` AND `(Int) -> Int` shape. Examples:
///    `_minimumCapacity(forScale:)`, `_maximumCapacity(forScale:)`,
///    `wordCount(forScale:)`, `_scale(forCapacity:)`. The idempotence
///    claim `f(f(scale)) == f(scale)` is meaningless — capacity-of-
///    capacity (or word-count-of-word-count) is a shape-coincidence,
///    not a fixed-point operation.
///
/// 2. **Formatter shape.** Function name matches `_description*` or
///    `format*` AND single-param shape. Examples: `_description(type:)`,
///    `format(_:)`. The idempotence claim `f(f(x))` doesn't type-check
///    for `format(_:) -> String` because re-formatting requires String
///    input which doesn't match the original parameter type; for
///    `_description(type:) (String) -> String` the claim would prepend
///    a structural wrapper twice.
///
/// Fires `Signal.vetoWeight` when either pattern matches. Wired into
/// `IdempotenceTemplate.suggest(for:)` (non-lifted path only).
///
/// Mechanism class: extension of class 7 (function-name + type-shape
/// composite, V1.14.1 / V1.16.1 / V1.21.C lineage). Third extension in
/// the lineage (SetAlgebra → math-forward → capacity/formatter).
extension IdempotenceTemplate {

    /// Returns a veto `Signal` when the summary matches one of the two
    /// shape-coincidence patterns. `nil` otherwise.
    ///
    /// Wired into `IdempotenceTemplate.suggest(for:)` alongside the
    /// existing `setAlgebraShapeVeto`, `mathForwardFunctionVeto`,
    /// `protocolCoverageVeto`, etc.
    static func shapeDisambiguationVeto(for summary: FunctionSummary) -> Signal? {
        // Common shape gate: single non-inout param, non-mutating,
        // non-Void return (the typeSymmetry shape gate from
        // typeSymmetrySignal). Re-checked here so the veto is robust
        // to call-site re-ordering.
        guard summary.parameters.count == 1,
              let param = summary.parameters.first,
              !param.isInout,
              !summary.isMutating,
              let returnType = summary.returnTypeText,
              returnType != "Void",
              returnType != "()" else {
            return nil
        }

        let name = summary.name

        // Pattern 1: capacity / scale domain conversion — `(Int) -> Int`
        // shape AND name contains a domain-conversion token AND first-
        // param label is a cross-domain marker. Both conditions required
        // to avoid false positives on curated idempotence verbs that
        // happen to use `forScale:` etc. (e.g., `normalize(forScale:)`).
        //
        // Catches both directions:
        //   - `_minimumCapacity(forScale:)` (capacity-FROM-scale)
        //   - `_scale(forCapacity:)` (scale-FROM-capacity; "Scale" / "scale" in name)
        //   - `wordCount(forScale:)` (Count token)
        // Skips: `normalize(forScale:)`, `simplify(forScale:)` (no
        // Capacity/Count/Scale token in name).
        if returnType == "Int", param.typeText == "Int" {
            let domainTokens = ["Capacity", "Count", "Scale", "scale"]
            let nameHit = domainTokens.contains { name.contains($0) }
            let labelHit: Bool = {
                guard let label = param.label else { return false }
                return label == "forScale" || label == "forCapacity"
            }()
            if nameHit, labelHit {
                let labelStr = param.label ?? "_"
                return Signal(
                    kind: .protocolCoveredProperty,
                    weight: Signal.vetoWeight,
                    detail: "Shape-coincidence: '\(name)(\(labelStr):)' is a "
                        + "cross-domain Int conversion (capacity↔scale family) "
                        + "with `(Int) -> Int` shape; `\(name)(\(name)(s))` "
                        + "is a type-shape coincidence, not an idempotent "
                        + "fixed-point operation"
                )
            }
        }

        // Pattern 2: formatter — `_description*` or `format*` name +
        // single-param shape. The claim `f(f(x))` fails either by
        // type-mismatch (format(_:) returns String for non-String input)
        // or by structural wrapping (e.g., _description prepends a type
        // wrapper that compounds).
        if name.hasPrefix("_description") || name.hasPrefix("format") {
            return Signal(
                kind: .protocolCoveredProperty,
                weight: Signal.vetoWeight,
                detail: "Shape-coincidence: '\(name)' is a formatter "
                    + "(prefix `_description`/`format`); `\(name)(\(name)(x))` "
                    + "either fails type-check (format returns String for "
                    + "non-String input) or compounds structural wrappers "
                    + "(_description prepends type info twice) — not idempotent"
            )
        }

        return nil
    }
}
