import SwiftInferCore

/// V1.16.1 — SetAlgebra-shape veto extension on `RoundTripTemplate`.
/// Closes post-v1.15 priority #1 (cycle-12 OC SetAlgebra round-trip
/// survivors: 2 `intersection ↔ subtracting`-shape pairs across
/// `OrderedSet+Partial SetAlgebra` extensions × `OrderedSet+UnorderedView`).
///
/// **Cycle-13 mechanism extension.** Replicates V1.14.1's function-name
/// + type-shape composite mechanism on round-trip — same structural
/// argument as inverse-pair: any pair drawn from
/// `{union, intersection, symmetricDifference, subtracting}` on
/// `Self`-typed shape is a SetAlgebra partial-application surface,
/// not a forward-reverse round-trip.
///
/// Consumes the V1.16.1-hoisted `SetAlgebraShape.isSelfTypedBinaryOp(_:)`
/// (lifted from `InversePairSetAlgebraShapeGate.swift`'s private helper
/// when round-trip + idempotence became consumers — second-consumer-
/// triggers-hoist pattern from v1.13).
///
/// File-split per the V1.6.1 / V1.8.1 / V1.10.1 / V1.11.1 / V1.12.1 /
/// V1.14.1 file-length precedent — keeps each calibration mechanism
/// in a self-contained file for attribution clarity.
extension RoundTripTemplate {

    /// Fires when both pair sides have `(Self) -> Self` shape AND both
    /// function names are in `SetAlgebraShape.binaryOps`. Returns a
    /// `-25` weight signal — calibrated for round-trip's `+30`
    /// typeSymmetry baseline; cleanly drops bare-shape pairs into
    /// Suppressed (clean margin from `+20` boundary).
    ///
    /// Score arithmetic (baseline `+30` typeSymmetry):
    /// - Bare typeSymmetry (`+30`) `- 25` = `+5` → Suppressed.
    /// - typeSymmetry + curated `encode/decode` (`+40`) `- 25` = `+45`
    ///   → Likely. (Hypothetical — `encode`/`decode` are unlikely to
    ///   coincide with SetAlgebra ops; if they do, the structural
    ///   argument still suppresses the SetAlgebra false-positive while
    ///   the curated-name signal preserves the legitimate user intent.)
    /// - typeSymmetry + cross-type counter (`-25`) `- 25` = `-20` →
    ///   Suppressed (deeper margin via additive composition).
    ///
    /// Weight `-25` (uniform with V1.14.1's inverse-pair calibration
    /// per V1.16.0 plan open decision #1).
    ///
    /// **Cycle-12 motivation.** The cycle-12 post-domain-marker-counter
    /// snapshot showed 2 OC round-trip survivors with this exact shape:
    /// `intersection(_:) ↔ subtracting(_:)` Self-typed pairs across
    /// `OrderedSet+Partial SetAlgebra` extensions × `UnorderedView`.
    /// Same false-positive class as V1.14.1's inverse-pair shape;
    /// V1.14.1 deliberately scoped to inverse-pair only, deferring
    /// round-trip + idempotence extension to cycle 13 (this release).
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
                + "SetAlgebra operations are partial applications, not "
                + "round-trip pairs (intersection ∘ subtracting is not "
                + "an identity-restoring chain)"
        )
    }
}
