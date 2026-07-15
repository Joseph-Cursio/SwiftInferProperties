import Foundation

/// Measured-verify Pass-1 composers for the three algebraic-law templates added
/// alongside the catalogue work: involution (`f(f(x)) == x`), binary-idempotence
/// (`op(x, x) == x`), and the additive-measure homomorphism
/// (`h(a + b) == h(a) + h(b)`). Each mirrors the shape of its closest existing
/// composer — involution is idempotence with the RHS changed to the input,
/// binary-idempotence is a one-value single-op check, and homomorphism reuses
/// the `idempotence-lifted` array-generation idiom.
extension StrategistDispatchEmitter {

    /// Dispatch for the three catalogue-work algebraic laws — `nil` for any
    /// other template so `defaultPassSection` falls through to its
    /// `unsupportedTemplate` error. Kept here so the main emitter's switch stays
    /// under the cyclomatic-complexity cap.
    static func algebraicLawPass(inputs: Inputs, recipe: GeneratorRecipe) -> String? {
        switch inputs.template {
        case "involution":
            return composeInvolutionPass(inputs: inputs, recipe: recipe)

        case "binary-idempotence":
            return composeBinaryIdempotencePass(inputs: inputs, recipe: recipe)

        case "homomorphism":
            return composeHomomorphismPass(inputs: inputs, recipe: recipe)

        default:
            return nil
        }
    }

    // MARK: - Involution (1 value per trial; f(f(x)) == x)

    static func composeInvolutionPass(inputs: Inputs, recipe: GeneratorRecipe) -> String {
        let functionCall = inputs.functionCalls.first ?? "(missing)"
        // A nullary non-mutating instance method returning its own type chains on
        // the receiver: `value.m().m() == value`.
        if inputs.isInstanceMethod, inputs.isNullary, inputs.returnsSelfType {
            return composeSelfReturningInvolutionPass(functionCall: functionCall, recipe: recipe)
        }
        let oracle = "\(functionCall)(\(functionCall)(candidate)) != candidate"
        let shrink = shrinkableScalarCarriers.contains(recipe.carrierTypeName)
            ? singleShrinkPhase(carrier: recipe.carrierTypeName, oracle: oracle)
            : ""
        return """
        // --- Pass 1: default (strategist-derived generator) ---
        // involution: applying `\(functionCall)` twice returns the original input.

        let defaultGenerator: Generator<\(recipe.carrierTypeName), some SendableSequenceType> =
            \(recipe.expression)

        for trial in 0 ..< trials {
            let value = defaultGenerator.run(using: &rng)
            let onceResult = \(functionCall)(value)
            let twiceResult = \(functionCall)(onceResult)
            if twiceResult != value {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: \\(value)")
                print("VERIFY_DEFAULT_FORWARD: \\(onceResult)")
                print("VERIFY_DEFAULT_INVERSE: \\(twiceResult)")
        \(shrink)
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    /// A nullary non-mutating self-returning instance-method involution:
    /// `value.m().m() == value`.
    private static func composeSelfReturningInvolutionPass(
        functionCall: String,
        recipe: GeneratorRecipe
    ) -> String {
        let methodName = functionCall.split(separator: ".").last.map(String.init) ?? functionCall
        return """
        // --- Pass 1: default (strategist-derived generator) ---
        // self-returning instance-method involution: applying `\(methodName)`
        // twice on the receiver returns the original.

        let defaultGenerator: Generator<\(recipe.carrierTypeName), some SendableSequenceType> =
            \(recipe.expression)

        for trial in 0 ..< trials {
            let value = defaultGenerator.run(using: &rng)
            let onceResult = value.\(methodName)()
            let twiceResult = onceResult.\(methodName)()
            if twiceResult != value {
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

    // MARK: - Binary idempotence (1 value per trial; op(x, x) == x)

    static func composeBinaryIdempotencePass(inputs: Inputs, recipe: GeneratorRecipe) -> String {
        let functionCall = inputs.functionCalls.first ?? "(missing)"
        let oracle = "\(functionCall)(candidate, candidate) != candidate"
        let shrink = shrinkableScalarCarriers.contains(recipe.carrierTypeName)
            ? singleShrinkPhase(carrier: recipe.carrierTypeName, oracle: oracle)
            : ""
        return """
        // --- Pass 1: default (strategist-derived generator) ---
        // binary idempotence: combining a value with itself is a no-op.

        let defaultGenerator: Generator<\(recipe.carrierTypeName), some SendableSequenceType> =
            \(recipe.expression)

        for trial in 0 ..< trials {
            let value = defaultGenerator.run(using: &rng)
            let result = \(functionCall)(value, value)
            if result != value {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: \\(value)")
                print("VERIFY_DEFAULT_FORWARD: \\(result)")
                print("VERIFY_DEFAULT_INVERSE: \\(value)")
        \(shrink)
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    // MARK: - Homomorphism (2 arrays per trial; h(a + b) == h(a) + h(b))

    /// The generator carrier is the array's ELEMENT type (the verify dispatch
    /// strips `[Int]` → `Int`), so — like `idempotence-lifted` — the element
    /// generator is wrapped in the kit's `.array(of:)` helper to draw arrays.
    static func composeHomomorphismPass(inputs: Inputs, recipe: GeneratorRecipe) -> String {
        let functionCall = inputs.functionCalls.first ?? "(missing)"
        return """
        // --- Pass 1: default (strategist-derived element + kit array helper) ---
        // additive-measure homomorphism: h(a + b) == h(a) + h(b) over arrays.

        let elementGenerator: Generator<\(recipe.carrierTypeName), some SendableSequenceType> =
            \(recipe.expression)
        let defaultGenerator: Generator<[\(recipe.carrierTypeName)], some SendableSequenceType> =
            elementGenerator.array(of: 0 ... 8)

        for trial in 0 ..< trials {
            let aValue = defaultGenerator.run(using: &rng)
            let bValue = defaultGenerator.run(using: &rng)
            let combined = \(functionCall)(aValue + bValue)
            let summed = \(functionCall)(aValue) + \(functionCall)(bValue)
            if combined != summed {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: (\\(aValue), \\(bValue))")
                print("VERIFY_DEFAULT_FORWARD: \\(combined)")
                print("VERIFY_DEFAULT_INVERSE: \\(summed)")
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }
}
