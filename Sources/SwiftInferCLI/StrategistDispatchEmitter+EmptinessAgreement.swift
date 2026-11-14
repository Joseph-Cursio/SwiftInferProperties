import SwiftInferCore
import SwiftInferTemplates

// The emptiness-agreement composer (#701), in its own file for the reason the
// sibling `+RangeLaws` / `+Differential` files exist: `+AlgebraicLaws` sits within
// a few composers of SwiftLint's 400-line cap. Dispatched from `algebraicLawPass`.
extension StrategistDispatchEmitter {

    // MARK: - Emptiness agreement (1 value per trial; a predicate and a count agree on it)

    /// **The emptiness agreement law** — `value.p == (value.m > 0)`, or `== 0` when `p` is
    /// `isEmpty`, for every drawn `value` of the members' declaring type.
    ///
    /// `functionCalls` are the two MEMBER SPELLINGS `resolveEmptinessAgreementCalls` wrote —
    /// `hasIssues`, `totalIssueCount()` — so whether each is a property or a method was settled
    /// from the index, not guessed here. The polarity is re-read from the two names with
    /// `EmptinessAgreementPairing.polarity`, as `accept` re-reads it, so the law verify runs is
    /// the law `accept` wrote.
    ///
    /// The oracle compares a `Bool` with a signed-integer comparison against a literal — the
    /// pairing guarantees both types (`returnTypeText == "Bool"`, `MeasureTemplate.isMeasure`) —
    /// so it asks for no conformance, not even `Equatable` on the carrier. One receiver value per
    /// trial, the draw `composeMeasureNonNegativityPass` uses.
    ///
    /// **A failure is an assertion, never a trap.** FORWARD prints `(predicate, count)` as read,
    /// INVERSE the law; neither `VERIFY_TRIAL_INPUT` nor `VERIFY_TRIAL_CARRIER` is printed,
    /// because `VerifyResultParser` reads a trap carrying those as a totality refutation, and a
    /// member that traps refutes nothing about agreement. It stays an `.error`.
    ///
    /// **Returns `nil` when the names do not pair or there are not two of them** — no polarity,
    /// no law. Unreachable through `buildStubBundle`, whose resolver refuses such an entry as
    /// stale first; kept so a direct caller gets the honest "no composer" rather than a guessed
    /// comparison. No shrink phase: the counterexample is one value of a user type.
    static func composeEmptinessAgreementPass(inputs: Inputs, recipe: GeneratorRecipe) -> String? {
        guard inputs.functionCalls.count == 2 else { return nil }
        let predicate = inputs.functionCalls[0]
        let measure = inputs.functionCalls[1]
        guard let polarity = EmptinessAgreementPairing.polarity(
            predicate: RoundTripPairResolver.stripParameterLabels(predicate),
            measure: RoundTripPairResolver.stripParameterLabels(measure)
        ) else { return nil }
        let comparison = polarity == .holdsWhenPositive ? "> 0" : "== 0"
        let law = "\(predicate) == (\(measure) \(comparison))"
        return """
        // --- Pass 1: default (strategist-derived generator) ---
        // emptiness agreement: `\(law)` — the predicate and the count describe one fact.

        let defaultGenerator: Generator<\(recipe.carrierTypeName), some SendableSequenceType> =
            \(recipe.expression)

        for trial in 0 ..< trials {
            let value = defaultGenerator.run(using: &rng)
            let holds: Bool = value.\(predicate)
            let measured = value.\(measure)
            if holds != (measured \(comparison)) {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: \\(value)")
                print("VERIFY_DEFAULT_FORWARD: (\\(holds), \\(measured))")
                print("VERIFY_DEFAULT_INVERSE: <\(law)>")
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }
}
