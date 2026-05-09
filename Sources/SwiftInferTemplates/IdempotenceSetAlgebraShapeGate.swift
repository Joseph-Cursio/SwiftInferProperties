import SwiftInferCore

/// V1.16.1 — SetAlgebra-shape veto extension on `IdempotenceTemplate`.
/// Closes post-v1.15 priority #1 (cycle-12 OC SetAlgebra idempotence
/// survivors: 4 `intersection`/`subtracting` Self-typed claims across
/// `OrderedSet+Partial SetAlgebra` extensions × `OrderedSet+UnorderedView`).
///
/// **Cycle-13 mechanism extension.** Replicates V1.14.1's function-name
/// + type-shape composite mechanism on idempotence — same structural
/// argument as inverse-pair + round-trip: any unary function drawn
/// from `{union, intersection, symmetricDifference, subtracting}` on
/// `Self`-typed shape is a SetAlgebra binary-op partial application
/// (`(other) -> result`), not a true self-mappable transformation
/// satisfying `f(f(x)) == f(x)` for unary `(T) -> T`.
///
/// Consumes the V1.16.1-hoisted `SetAlgebraShape.isSelfTypedBinaryOp(_:)`
/// (lifted from `InversePairSetAlgebraShapeGate.swift`'s private helper
/// when round-trip + idempotence became consumers).
///
/// File-split per the V1.6.1 / V1.8.1 / V1.10.1 / V1.11.1 / V1.12.1 /
/// V1.14.1 file-length precedent.
extension IdempotenceTemplate {

    /// Fires when the candidate has `(Self) -> Self` shape AND its
    /// function name is in `SetAlgebraShape.binaryOps`. Returns a
    /// `-25` weight signal — calibrated for idempotence's `+30`
    /// typeSymmetry baseline; cleanly drops bare-shape candidates
    /// into Suppressed (clean margin from `+20` boundary).
    ///
    /// Score arithmetic (baseline `+30` typeSymmetry):
    /// - Bare typeSymmetry (`+30`) `- 25` = `+5` → Suppressed.
    /// - typeSymmetry + curated verb (`+40`) `- 25` = `+45` → Likely.
    ///   (Hypothetical — `normalize` / `trim` etc. don't normally
    ///   coincide with SetAlgebra ops; if they do, the structural
    ///   argument still suppresses the SetAlgebra false-positive.)
    ///
    /// Weight `-25` (uniform with V1.14.1's inverse-pair calibration
    /// + V1.16.1's round-trip calibration per V1.16.0 plan open
    /// decision #1).
    ///
    /// **Cycle-12 motivation.** The cycle-12 post-domain-marker-counter
    /// snapshot showed 4 OC idempotence survivors with this shape:
    /// `intersection(_:)` × 2, `subtracting(_:)` × 2, all
    /// `(Self) -> Self` typed across `OrderedSet+Partial SetAlgebra`
    /// extensions and `OrderedSet+UnorderedView` declarations.
    static func setAlgebraShapeVeto(
        for summary: FunctionSummary
    ) -> Signal? {
        guard SetAlgebraShape.isSelfTypedBinaryOp(summary),
              SetAlgebraShape.binaryOps.contains(summary.name) else {
            return nil
        }
        return Signal(
            kind: .protocolCoveredProperty,
            weight: -25,
            detail: "SetAlgebra-shape function: '\(summary.name)' on "
                + "Self-typed binary op — SetAlgebra operations are "
                + "partial applications ((other) -> result), not "
                + "self-mappable unary transformations"
        )
    }
}
