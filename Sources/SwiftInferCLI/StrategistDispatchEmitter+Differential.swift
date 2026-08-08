import Foundation
import PropertyLawCore
import SwiftInferCore

// The `differential-equivalence` composer, in its own file for the reason the
// sibling `+AlgebraicLaws` / `+Recursion` files exist: `+Templates` sits against
// SwiftLint's 400-line file cap, and this law was the two lines that pushed it
// over. Splitting is the standing remedy here — the cap is not negotiated and
// the alternative is trimming a rationale that records a measurement.
extension StrategistDispatchEmitter {

    // MARK: - Differential equivalence (1 value per trial; reference(x) == variant(x))

    /// Sibling of `totalityLawPass`, checked before `algebraicLawPass` for the
    /// same reason: `differential-equivalence` is in `strategistAlgebraicLaws`
    /// (it is verifiable and not one of the three excluded), but its law is a
    /// comparison of two calls on one input rather than an algebraic identity,
    /// so the algebraic switch cannot compose it and would reject it with an
    /// `unsupportedTemplate` naming a set it IS in — the most confusing error
    /// available.
    static func differentialLawPass(inputs: Inputs, recipe: GeneratorRecipe) throws -> String? {
        guard inputs.template == TemplateName.differentialEquivalence.rawValue else { return nil }
        return try composeDifferentialPass(inputs: inputs, recipe: recipe)
    }

    /// **Differential / oracle equivalence** — two implementations of one
    /// specification agree on every input.
    ///
    /// Structurally the simplest two-call law in the set: one generated value,
    /// two independent calls, compare. `round-trip` looks similar but *nests*
    /// (`inverse(forward(x)) == x`), so its intermediate has the forward's
    /// return type; here both calls take the same input and their results are
    /// compared directly, which is why the two composers do not share a body.
    ///
    /// The counterexample prints **both results**, not just the mismatch. A
    /// differential refutation names two functions and does not say which is
    /// wrong — the law is that they agree, and it is silent about who is at
    /// fault. Printing both is what lets a reader make that call, and it is why
    /// the renderer phrases this law with the variant as the subject and the
    /// reference as the expectation rather than as a round trip.
    static func composeDifferentialPass(
        inputs: Inputs,
        recipe: GeneratorRecipe
    ) throws -> String {
        guard inputs.functionCalls.count == 2 else {
            throw VerifyError.unsupportedTemplate(
                template: "differential-equivalence",
                expected: ["functionCalls must be [referenceCall, variantCall]"]
            )
        }
        let reference = inputs.functionCalls[0]
        let variant = inputs.functionCalls[1]
        let oracle = "\(variant)(candidate) != \(reference)(candidate)"
        let shrink = shrinkableScalarCarriers.contains(recipe.carrierTypeName)
            ? singleShrinkPhase(carrier: recipe.carrierTypeName, oracle: oracle)
            : ""
        return """
        // --- Pass 1: default (strategist-derived generator) ---

        let defaultGenerator: Generator<\(recipe.carrierTypeName), some SendableSequenceType> =
            \(recipe.expression)

        for trial in 0 ..< trials {
            let value = defaultGenerator.run(using: &rng)
            let referenceResult = \(reference)(value)
            let variantResult = \(variant)(value)
            if variantResult != referenceResult {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: \\(value)")
                print("VERIFY_DEFAULT_FORWARD: \\(referenceResult)")
                print("VERIFY_DEFAULT_INVERSE: \\(variantResult)")
        \(shrink)
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }
}
