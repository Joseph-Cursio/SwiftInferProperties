import Foundation

// V1.47.E — per-template Pass 1 composers for the strategist-routed
// emitter. Each composer renders the same shape its v1.46-hardcoded
// counterpart would (`RoundTripStubEmitter.composeIntSource`,
// `IdempotenceStubEmitter+NonComplex.intDefaultPass`, etc.) but with
// the strategist-derived generator expression in place of the carrier-
// specific inlined factory.
//
// Equality is `!=` for all v1.47 strategist-routed carriers (Int /
// String / Bool / fixed-width / enums). Floating-point carriers stay
// on the v1.46 hardcoded path, so `isApproximatelyEqual` isn't needed
// here.
extension StrategistDispatchEmitter {

    // MARK: - Round-trip (1 value per trial)

    static func composeRoundTripPass(
        inputs: Inputs,
        recipe: GeneratorRecipe
    ) throws -> String {
        guard inputs.functionCalls.count == 2 else {
            throw VerifyError.unsupportedTemplate(
                template: "round-trip",
                expected: ["functionCalls must be [forwardCall, inverseCall]"]
            )
        }
        let forward = inputs.functionCalls[0]
        let inverse = inputs.functionCalls[1]
        return """
        // --- Pass 1: default (strategist-derived generator) ---

        let defaultGenerator: Generator<\(recipe.carrierTypeName), some SendableSequenceType> =
            \(recipe.expression)

        for trial in 0 ..< trials {
            let value = defaultGenerator.run(using: &rng)
            let forwardResult = \(forward)(value)
            let inverseResult = \(inverse)(forwardResult)
            if inverseResult != value {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: \\(value)")
                print("VERIFY_DEFAULT_FORWARD: \\(forwardResult)")
                print("VERIFY_DEFAULT_INVERSE: \\(inverseResult)")
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    // MARK: - Idempotence (1 value per trial; f(f(x)) == f(x))

    static func composeIdempotencePass(
        inputs: Inputs,
        recipe: GeneratorRecipe
    ) -> String {
        let functionCall = inputs.functionCalls.first ?? "(missing)"
        return """
        // --- Pass 1: default (strategist-derived generator) ---

        let defaultGenerator: Generator<\(recipe.carrierTypeName), some SendableSequenceType> =
            \(recipe.expression)

        for trial in 0 ..< trials {
            let value = defaultGenerator.run(using: &rng)
            let onceResult = \(functionCall)(value)
            let twiceResult = \(functionCall)(onceResult)
            if onceResult != twiceResult {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: \\(value)")
                print("VERIFY_DEFAULT_FORWARD: \\(onceResult)")
                print("VERIFY_DEFAULT_INVERSE: \\(twiceResult)")
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    // MARK: - Commutativity (2 values per trial; f(a, b) == f(b, a))

    static func composeCommutativityPass(
        inputs: Inputs,
        recipe: GeneratorRecipe
    ) -> String {
        let functionCall = inputs.functionCalls.first ?? "(missing)"
        return """
        // --- Pass 1: default (strategist-derived generator) ---

        let defaultGenerator: Generator<\(recipe.carrierTypeName), some SendableSequenceType> =
            \(recipe.expression)

        for trial in 0 ..< trials {
            let lhs = defaultGenerator.run(using: &rng)
            let rhs = defaultGenerator.run(using: &rng)
            let lhsResult = \(functionCall)(lhs, rhs)
            let rhsResult = \(functionCall)(rhs, lhs)
            if lhsResult != rhsResult {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: (\\(lhs), \\(rhs))")
                print("VERIFY_DEFAULT_FORWARD: \\(lhsResult)")
                print("VERIFY_DEFAULT_INVERSE: \\(rhsResult)")
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    // MARK: - Associativity (3 values per trial; f(f(a, b), c) == f(a, f(b, c)))

    static func composeAssociativityPass(
        inputs: Inputs,
        recipe: GeneratorRecipe
    ) -> String {
        let functionCall = inputs.functionCalls.first ?? "(missing)"
        return """
        // --- Pass 1: default (strategist-derived generator) ---

        let defaultGenerator: Generator<\(recipe.carrierTypeName), some SendableSequenceType> =
            \(recipe.expression)

        for trial in 0 ..< trials {
            let valueA = defaultGenerator.run(using: &rng)
            let valueB = defaultGenerator.run(using: &rng)
            let valueC = defaultGenerator.run(using: &rng)
            let lhsResult = \(functionCall)(\(functionCall)(valueA, valueB), valueC)
            let rhsResult = \(functionCall)(valueA, \(functionCall)(valueB, valueC))
            if lhsResult != rhsResult {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: (\\(valueA), \\(valueB), \\(valueC))")
                print("VERIFY_DEFAULT_FORWARD: \\(lhsResult)")
                print("VERIFY_DEFAULT_INVERSE: \\(rhsResult)")
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }
}
