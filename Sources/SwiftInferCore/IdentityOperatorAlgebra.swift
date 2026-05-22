/// V1.29.B — curated algebraic-family sets for the IdentityElementTemplate
/// naming-signal gate. Closes cycle-25 finding 2: `rescaledDivide(_:_:) ×
/// Complex.zero` was a 6-cycle stable reject (cycles 17 + 20 + 23 + 25)
/// because the `+40` curated-identity-constant signal in `identityNaming-
/// Signal` fires unconditionally on type-shape match without checking that
/// the operator and identity-constant belong to a compatible algebraic
/// family.
///
/// Two consumer sets:
///
/// 1. **`additiveOperatorNames`** — operator names for which `T.zero` is
///    the (right or two-sided) identity. The identity `T.zero` fires only
///    when the op is additive; non-additive ops trigger
///    `algebraicFamilyMismatchVeto` instead.
///
/// 2. **`multiplicativeOperatorNames`** — operator names for which `T.one`
///    is the (right or two-sided) identity. Symmetric to (1).
///
/// `.empty` and `.identity` constants are handled by the existing
/// `identityCoverageCandidate` op-class map (V1.5.2); they don't need
/// the algebraic-family gate. `.none` and `.default` are ambiguous and
/// already fall through without coverage.
///
/// Mechanism-class extension: extends class 6 (identity-element template
/// signal arithmetic) with V1.29.B's algebraic-family check. The curated
/// sets are intentionally conservative — extension in future cycles via
/// project vocabulary is the supported path.
public enum IdentityOperatorAlgebra {

    /// Operator names for which `T.zero` is the algebraic identity.
    ///
    /// Includes the canonical infix `+`, the method-spelled equivalents
    /// (`add`, `plus`), the precision-relaxed swift-numerics variant
    /// (`_relaxedAdd`), and the FMA-shaped `addingProduct` (whose left
    /// arg sees `T.zero` as a no-op when the product cleanly evaluates).
    ///
    /// **Excludes** `-` deliberately: subtraction has only a right
    /// identity (`a - 0 == a`), not two-sided (`0 - a == -a ≠ a`). The
    /// two-sidedness check in the emitted property would fail; reject
    /// at signal time.
    public static let additiveOperatorNames: Set<String> = [
        "+",
        "add",
        "plus",
        "addingProduct",
        "_relaxedAdd"
    ]

    /// Operator names for which `T.one` is the algebraic identity.
    ///
    /// Includes the canonical infix `*`, method-spelled equivalents
    /// (`multiply`, `times`), and the precision-relaxed swift-numerics
    /// variant (`_relaxedMul`).
    ///
    /// **Excludes** `/` deliberately: division is not commutative and
    /// has only a right identity (`a / 1 == a`), not two-sided (`1 / a
    /// == 1/a ≠ a` for `a ≠ 1`).
    public static let multiplicativeOperatorNames: Set<String> = [
        "*",
        "multiply",
        "times",
        "_relaxedMul"
    ]

    /// Returns `true` when the `(identityName, opName)` combination is
    /// algebraically incompatible — i.e., the curated identity constant
    /// is NOT the algebraic identity of the operator. Used by
    /// `IdentityElementTemplate.algebraicFamilyMismatchVeto` to fire a
    /// full veto on type-shape false-positives like `rescaledDivide(_:_:)
    /// × Complex.zero`.
    ///
    /// Only checks the `zero` + `one` constants; `.empty`, `.identity`,
    /// `.none`, `.default` are unaffected (handled by existing paths or
    /// intentionally fall through).
    public static func isIncompatibleFamily(
        identityName: String,
        opName: String
    ) -> Bool {
        switch identityName {
        case "zero":
            return !additiveOperatorNames.contains(opName)

        case "one":
            return !multiplicativeOperatorNames.contains(opName)

        default:
            return false
        }
    }
}
