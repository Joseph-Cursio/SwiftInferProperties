import Foundation

/// V1.45.A — synthesizes the standalone Swift source for a
/// commutativity verify subprocess (`f(a, b) ≈ f(b, a)` on a binary
/// function `f: (T, T) -> T`).
///
/// **Shape parity with the v1.44 emitters.** Same two-pass design,
/// same Xoshiro seeded RNG, same `VERIFY_DEFAULT_*` / `VERIFY_EDGE_*`
/// stdout-marker contract. `VerifyResultParser` consumes commutativity
/// output unchanged.
///
/// **Marker field semantics.** `VERIFY_*_INPUT` carries the pair as a
/// single string (`"(lhs, rhs)"`); `VERIFY_*_FORWARD` carries
/// `f(lhs, rhs)` (the original-order result) and `VERIFY_*_INVERSE`
/// carries `f(rhs, lhs)` (the swapped-order result). The V1.44.D
/// renderer reads `templateName` to phrase these correctly.
///
/// **Two-value generation.** Each trial draws two `T` values from the
/// per-carrier generator. For the Complex<Double> / Double edge
/// passes, the **first** value is biased to the edge generator and
/// the **second** is drawn from the default finite generator. This
/// gives `~10 edge × finite` pairings per 100 trials (vs `~1 edge ×
/// edge` if both were biased), surfacing the advisory signal at half
/// the cost — symmetric pairing would compound the point-at-infinity
/// equality collapse on Complex.
///
/// **Carrier scope (V1.45.A).** Same set as `IdempotenceStubEmitter`
/// post-V1.44.C: `Complex<Double>`, `Double`, `Int`.
public enum CommutativityStubEmitter: SeededStubEmitter {

    /// Seed-hex format shared with `RoundTripStubEmitter`.
    public typealias SeedHex = RoundTripStubEmitter.SeedHex

    /// Trial budget shared with `RoundTripStubEmitter`.
    public typealias TrialBudget = RoundTripStubEmitter.TrialBudget

    /// Inputs to the emitter — shared with the other seeded algebraic
    /// emitters; see ``SeededCarrierStubInputs``. This emitter's rendering of
    /// `functionCall` is described in the type documentation above.
    public typealias Inputs = SeededCarrierStubInputs

    /// V1.45.A's supported carrier set — mirrors V1.44 emitters.
    public static let supportedCarriers: [String] = ["Complex<Double>", "Double", "Int"]

    /// Emit a commutativity verify stub. Validates the carrier first,
    /// then dispatches to the per-carrier composer.
    public static func emit(_ inputs: Inputs) throws -> String {
        try CarrierStubDispatch.emit(
            inputs,
            supportedCarriers: supportedCarriers,
            complexDouble: composeComplexDoubleSource,
            double: composeDoubleSource,
            int: composeIntSource
        )
    }
}
