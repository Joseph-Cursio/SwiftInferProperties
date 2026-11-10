/// V1.46.A — synthesizes the standalone Swift source for an
/// associativity verify subprocess
/// (`f(f(a, b), c) ≈ f(a, f(b, c))` on a binary function
/// `f: (T, T) -> T`).
///
/// **Shape parity with the v1.45 commutativity emitter.** Same two-pass
/// design, same Xoshiro seeded RNG, same `VERIFY_DEFAULT_*` /
/// `VERIFY_EDGE_*` stdout-marker contract. `VerifyResultParser` consumes
/// associativity output unchanged.
///
/// **Marker field semantics.** `VERIFY_*_INPUT` carries the triple as a
/// single string (`"(a, b, c)"`); `VERIFY_*_FORWARD` carries the
/// left-associated result `f(f(a, b), c)` and `VERIFY_*_INVERSE`
/// carries the right-associated result `f(a, f(b, c))`. The renderer
/// reads `templateName` to phrase these correctly.
///
/// **Three-value generation.** Each trial draws three `T` values from
/// the per-carrier generator. For the Complex<Double> / Double edge
/// passes, exactly one value per trial is drawn from the edge generator
/// — **per-slot rotation**: trial `t` puts the edge value in slot
/// `t % 3` (0 = `a`, 1 = `b`, 2 = `c`) and the other two slots draw
/// from the default finite generator. Over 100 trials this gives
/// ~34 / 33 / 33 edge draws per slot, surfacing associativity breaks
/// at any of the three nesting positions. A new `VERIFY_EDGE_SLOT`
/// marker line carries the slot index of the edge value on FAIL; the
/// parser ignores unknown marker lines, so this is purely advisory.
///
/// **Carrier scope (V1.46.A).** Same set as `CommutativityStubEmitter`
/// post-V1.45.A: `Complex<Double>`, `Double`, `Int`.
public enum AssociativityStubEmitter: SeededStubEmitter {

    /// Seed-hex format shared with `RoundTripStubEmitter`.
    public typealias SeedHex = RoundTripStubEmitter.SeedHex

    /// Trial budget shared with `RoundTripStubEmitter`.
    public typealias TrialBudget = RoundTripStubEmitter.TrialBudget

    /// Inputs to the emitter — shared with the other seeded algebraic
    /// emitters; see ``SeededCarrierStubInputs``. This emitter's rendering of
    /// `functionCall` is described in the type documentation above.
    public typealias Inputs = SeededCarrierStubInputs

    /// V1.46.A's supported carrier set — mirrors V1.45.A.
    public static let supportedCarriers: [String] = ["Complex<Double>", "Double", "Int"]

    /// Emit an associativity verify stub. Validates the carrier first,
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
