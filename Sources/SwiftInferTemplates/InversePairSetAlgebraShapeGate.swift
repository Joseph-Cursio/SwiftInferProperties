import SwiftInferCore

/// V1.14.1 — SetAlgebra-shape veto extension on `InversePairTemplate`.
/// Closes post-v1.13 priority #1 (cycle-9 OC inverse-pair survivors:
/// 6 `intersection ↔ subtracting`-shape pairs across `OrderedSet+
/// Partial SetAlgebra intersection.swift` × `OrderedSet+Partial SetAlgebra
/// subtracting.swift` × `OrderedSet+UnorderedView.swift`).
///
/// First **function-name + type-shape composite mechanism** in the
/// calibration loop, distinct from cycles 7-9's parameter-label-based
/// class. The structural argument "any pair drawn from `{union,
/// intersection, symmetricDifference, subtracting}` is not an inverse
/// pair" holds regardless of whether the carrier formally conforms to
/// `SetAlgebra` — `intersection` then `subtracting` does not recover
/// the original input, mathematically.
///
/// **Shape-only check (no protocol-conformance lookup).** Per V1.14.0
/// plan open decision #3: `OrderedSet` itself doesn't declare
/// `: SetAlgebra` (only `Partial SetAlgebra` extensions); a conformance
/// check would miss 4 of 6 cycle-9 OC survivors. Shape-only catches
/// all 6 by matching curated names + `Self`-typed param/return on both
/// sides.
///
/// File-split per the V1.6.1 / V1.8.1 / V1.10.1 / V1.11.1 / V1.12.1
/// file-length precedent — keeps each calibration mechanism in a
/// self-contained file for attribution clarity.
extension InversePairTemplate {

    /// Fires when both pair sides have `(Self) -> Self` shape AND both
    /// function names are in `SetAlgebraShape.binaryOps`. Returns a
    /// `-25` weight signal — calibrated for inverse-pair's `+25`
    /// typeSymmetry baseline; cleanly drops bare-shape pairs into
    /// Suppressed (clean margin from `+20` boundary).
    ///
    /// Score arithmetic:
    /// - Bare typeSymmetry (`+25`) `- 25` = `0` → Suppressed.
    /// - typeSymmetry + curated name (`+10`) `- 25` = `+10` →
    ///   Suppressed (still suppressed; curated `parse/format`-style
    ///   names are unlikely to coincide with SetAlgebra ops, but if
    ///   they do the structural argument still wins).
    ///
    /// **Self-typed shape requirement.** Both pair sides must have
    /// forward param + return type both `"Self"`. The 6 cycle-9 OC
    /// survivors all have this exact textual shape. A future
    /// SemanticIndex-aware version (PRD §20 v1.1+) could extend to
    /// "any `T -> T` binary op on a SetAlgebra-conforming carrier"
    /// once textual-only conformance resolution lifts.
    ///
    /// **Why a non-veto counter (`-25`) rather than full veto
    /// (`vetoWeight`).** Per V1.14.0 plan open decision #1: the rule
    /// has non-zero false-positive risk on custom types whose
    /// `intersection`/`subtracting`-named methods happen to be true
    /// inverses for some weird domain. A non-veto counter at the
    /// calibrated weight preserves recall on those edge cases via
    /// the curated/project name `+10` interaction (`+25 + 10 - 25 =
    /// +10`, still Suppressed); a future cycle could escalate to
    /// full veto if the false-positive risk turns out empty.
    static func setAlgebraShapeVeto(
        for pair: FunctionPair
    ) -> Signal? {
        guard SetAlgebraShape.isSelfTypedBinaryOp(pair.forward),
              SetAlgebraShape.isSelfTypedBinaryOp(pair.reverse),
              SetAlgebraShape.binaryOps.contains(pair.forward.name),
              SetAlgebraShape.binaryOps.contains(pair.reverse.name) else {
            return nil
        }
        return Signal(
            kind: .protocolCoveredProperty,
            weight: -25,
            detail: "SetAlgebra-shape pair: '\(pair.forward.name)' ↔ "
                + "'\(pair.reverse.name)' on Self-typed binary ops — "
                + "SetAlgebra operations do not form an inverse pair "
                + "(intersection ∘ subtracting ≠ identity)"
        )
    }
}
