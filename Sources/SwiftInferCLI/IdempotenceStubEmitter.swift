import Foundation

/// V1.44.A / V1.44.C — synthesizes the standalone Swift source for an
/// idempotence verify subprocess (`f(f(x)) ≈ f(x)` on a single function
/// `f: T -> T`).
///
/// **Shape parity with `RoundTripStubEmitter`.** Same two-pass design,
/// same Xoshiro seeded RNG, same `VERIFY_DEFAULT_*` / `VERIFY_EDGE_*`
/// stdout-marker contract. The V1.43.C parser (`VerifyResultParser`)
/// consumes the markers without modification.
///
/// **Marker field semantics differ from round-trip.** The parser fills
/// `forwardResult` ← `VERIFY_*_FORWARD` and `inverseResult` ← `VERIFY_*_INVERSE`
/// regardless of template; for idempotence these map to `f(x)`
/// (`onceResult`) and `f(f(x))` (`twiceResult`) respectively. The
/// V1.44.D renderer interprets the marker fields per template name.
///
/// **Carrier scope (V1.44.C).** Three carriers — same set as
/// `RoundTripStubEmitter` post-V1.44.B:
///
///   - `Complex<Double>`: two-pass (default finite + `Gen<Complex<Double>>.edgeCaseBiased()`).
///   - `Double`: two-pass with inlined `doubleWithNaN` equivalent.
///   - `Int`: single-pass with inlined `boundedForArithmetic` equivalent
///     + zero-edge sentinel so `VerifyResultParser` still produces `.bothPass`.
public enum IdempotenceStubEmitter: SeededStubEmitter {

    /// Seed-hex format shared with `RoundTripStubEmitter`.
    public typealias SeedHex = RoundTripStubEmitter.SeedHex

    /// Trial budget shared with `RoundTripStubEmitter`.
    public typealias TrialBudget = RoundTripStubEmitter.TrialBudget

    /// Inputs to the emitter — shared with the other seeded algebraic
    /// emitters; see ``SeededCarrierStubInputs``. This emitter's rendering of
    /// `functionCall` is described in the type documentation above.
    public typealias Inputs = SeededCarrierStubInputs

    /// V1.44.C's supported carrier set — mirrors `RoundTripStubEmitter`.
    public static let supportedCarriers: [String] = ["Complex<Double>", "Double", "Int"]

    /// Emit an idempotence verify stub. Validates the carrier first,
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

    // MARK: - Carrier dispatch
}
