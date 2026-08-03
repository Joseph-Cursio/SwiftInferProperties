import Foundation
import SwiftInferCore

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
        let oracle = "\(inverse)(\(forward)(candidate)) != candidate"
        let shrink = shrinkableScalarCarriers.contains(recipe.carrierTypeName)
            ? singleShrinkPhase(carrier: recipe.carrierTypeName, oracle: oracle)
            : ""
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
        \(shrink)
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    // MARK: - Codable round-trip (1 value per trial; decode(encode(x)) == x via JSON)

    /// The measured half of `CodableRoundTripTemplate` on the live-index path.
    /// Unlike `composeRoundTripPass` there is no forward/inverse function pair —
    /// the oracle is the carrier's own `Codable` conformance, exercised through
    /// `JSONEncoder` / `JSONDecoder` (the concrete coder named in the template's
    /// caveat). A codec that throws for a generated value is a round-trip failure
    /// too. `Foundation` is already in every strategist recipe's imports.
    /// The collision sweep's per-trial body for idempotence, hoisted out of the
    /// composer so it stays under the body-length cap. Binds locals before
    /// comparing: `functionCall` can be a closure literal, and
    /// `if { … }(x) != …` parses as a trailing closure.
    static func composeIdempotencePass(
        inputs: Inputs,
        recipe: GeneratorRecipe
    ) -> String {
        let functionCall = inputs.functionCalls.first ?? "(missing)"
        // Nullary mutating instance method → `var copy = value;
        // copy.method()` (V1.60.A). Now driven by the SemanticIndex
        // callee-shape signal so it generalizes beyond the curated OC
        // carriers; the `mutatingInstanceCarriers` set is retained as a
        // belt-and-suspenders OR for entries persisted without the signal.
        let mutatingInstance =
            (inputs.isInstanceMethod && inputs.isMutatingMethod && inputs.isNullary)
            || mutatingInstanceCarriers.contains(recipe.carrierTypeName)
        if mutatingInstance {
            return composeMutatingIdempotencePass(
                functionCall: functionCall,
                recipe: recipe
            )
        }
        // Nullary non-mutating instance method returning its own type →
        // chain the receiver: `value.method().method() == value.method()`.
        if inputs.isInstanceMethod, inputs.isNullary, inputs.returnsSelfType {
            return composeSelfReturningIdempotencePass(
                functionCall: functionCall,
                recipe: recipe
            )
        }
        // Self-returning instance method taking one operand → idempotence IN
        // THE OPERAND: `a.merge(b).merge(b) == a.merge(b)`. Mirrors
        // `Verify.takesOperandIdempotenceShape`, which is what routed a
        // label-carrying receiver closure here instead of a static reference.
        if inputs.isInstanceMethod, !inputs.isMutatingMethod,
            !inputs.isNullary, inputs.returnsSelfType, inputs.parameterCount == 1 {
            return composeOperandIdempotencePass(
                functionCall: functionCall,
                recipe: recipe
            )
        }
        return composeDirectIdempotencePass(functionCall: functionCall, recipe: recipe)
    }

    // MARK: - Commutativity (2 values per trial; f(a, b) == f(b, a))

    /// Routes the one template whose law is neither algebraic nor comparison-based.
    ///
    /// A sibling of `algebraicLawPass` and deliberately checked *before* it: `predicate` is in
    /// `TemplateName.verifiable` but excluded from `strategistAlgebraicLaws`, so the algebraic
    /// fallthrough would reject it with an `unsupportedTemplate` naming a set it was never in.
    static func totalityLawPass(inputs: Inputs, recipe: GeneratorRecipe) -> String? {
        guard inputs.template == TemplateName.predicate.rawValue else { return nil }
        return composePredicatePass(inputs: inputs, recipe: recipe)
    }

    /// **Totality** — the predicate returns a value for every input its type admits.
    ///
    /// The only composer whose law fails by **trap** rather than by assertion, and the whole shape
    /// follows from that. A trapping predicate kills the process: no `VERIFY_DEFAULT_RESULT` is
    /// printed, the exit is a signal rather than 0 or 1, and `VerifyResult.parse` rule 4 would file
    /// it under `.error` — the same bucket as a broken build. The most valuable outcome this law
    /// can produce would read as instrument failure.
    ///
    /// So the input is printed **before** the call. On a trap the last marker names the
    /// counterexample, and `parse`'s trap branch turns it into a `.defaultFails` with that input.
    ///
    /// This works only because `SeededStubEmitter` opens every stub with
    /// `setvbuf(stdout, nil, _IONBF, 0)` — `print` is block-buffered into a pipe, which is exactly
    /// how the verifier is run, so without it a trap would discard every marker printed before it.
    /// That preamble is load-bearing for this composer specifically; the other twelve never need a
    /// marker to survive a crash.
    ///
    /// There is no `!=` oracle here: a predicate that *returns* has satisfied the law. The result
    /// is bound to `_` deliberately — reading it would invite a reader to think the VALUE is being
    /// checked, and it is not. What this law owes, and all it owes, is that a value came back.
    static func composePredicatePass(
        inputs: Inputs,
        recipe: GeneratorRecipe
    ) -> String {
        let functionCall = inputs.functionCalls.first ?? "(missing)"
        return """
        // --- Pass 1: default (strategist-derived generator) ---
        //
        // TOTALITY. The predicate must return for every input its type admits. A violation is a
        // TRAP, not a false comparison, so it cannot be caught here — the marker printed before
        // each call is what survives the crash and names the input. Relies on the unbuffered
        // stdout the stub preamble sets.

        let defaultGenerator: Generator<\(recipe.carrierTypeName), some SendableSequenceType> =
            \(recipe.expression)

        for trial in 0 ..< trials {
            let candidate = defaultGenerator.run(using: &rng)
            // BEFORE the call: if the next line traps, this is the counterexample.
            print("VERIFY_TRIAL_INDEX: \\(trial)")
            print("VERIFY_TRIAL_INPUT: \\(candidate)")
            // Bound to `_` on purpose: totality is satisfied by RETURNING. The value is not the law.
            _ = \(functionCall)(candidate)
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    static func composeCommutativityPass(
        inputs: Inputs,
        recipe: GeneratorRecipe
    ) -> String {
        let functionCall = inputs.functionCalls.first ?? "(missing)"
        let oracle = "\(functionCall)(aValue, bValue) != \(functionCall)(bValue, aValue)"
        let shrink = shrinkableScalarCarriers.contains(recipe.carrierTypeName)
            ? pairShrinkPhase(carrier: recipe.carrierTypeName, oracle: oracle)
            : ""
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
        \(shrink)
                exit(1)
            }
        }

        \(CollisionPass.binarySweep(functionCall: functionCall, carrier: recipe.carrierTypeName))

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
        let oracle = "\(functionCall)(\(functionCall)(aValue, bValue), cValue)"
            + " != \(functionCall)(aValue, \(functionCall)(bValue, cValue))"
        let shrink = shrinkableScalarCarriers.contains(recipe.carrierTypeName)
            ? tripleShrinkPhase(carrier: recipe.carrierTypeName, oracle: oracle)
            : ""
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
        \(shrink)
                exit(1)
            }
        }

        \(CollisionPass.ternarySweep(functionCall: functionCall, carrier: recipe.carrierTypeName))

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    // MARK: - V1.48.A Idempotence-lifted (1 collection per trial; f(f(xs)) == f(xs))

    /// Wraps the strategist's element generator in
    /// `Gen<[Element]>` via the kit's
    /// `Generator<T>.array(of: ClosedRange<Int>)` helper
    /// (`PropertyBased/Gen+Collection.swift`). Each trial draws a
    /// random-length array (size 0–8) and asserts the lifted
    /// function is idempotent on the array.
    static func composeIdempotenceLiftedPass(
        inputs: Inputs,
        recipe: GeneratorRecipe
    ) -> String {
        let functionCall = inputs.functionCalls.first ?? "(missing)"
        return """
        // --- Pass 1: default (strategist-derived element + kit array helper) ---

        let elementGenerator: Generator<\(recipe.carrierTypeName), some SendableSequenceType> =
            \(recipe.expression)
        let defaultGenerator: Generator<[\(recipe.carrierTypeName)], some SendableSequenceType> =
            elementGenerator.array(of: 0 ... 8)

        for trial in 0 ..< trials {
            let xs = defaultGenerator.run(using: &rng)
            let onceResult = \(functionCall)(xs)
            let twiceResult = \(functionCall)(onceResult)
            if onceResult != twiceResult {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: \\(xs)")
                print("VERIFY_DEFAULT_FORWARD: \\(onceResult)")
                print("VERIFY_DEFAULT_INVERSE: \\(twiceResult)")
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    // MARK: - V1.48.A Dual-style-consistency

    // The dual-style-consistency composers (`composeDualStyleConsistencyPass`
    // + `composeMutatingDualStylePass` + the `dualStyleNonMutatingCallExpression`
    // / `dualStyleTrailingArgument` helpers) live in
    // `StrategistDispatchEmitter+DualStyle.swift` — extracted so this file
    // stays under SwiftLint's file-length cap.

    // MARK: - V1.48.A Monotonicity

    // The monotonicity composers (`composeMonotonicityPass` +
    // `composeInstanceMethodMonotonicityPass`) live in
    // `StrategistDispatchEmitter+Monotonicity.swift` — extracted V1.69
    // so this file stays under SwiftLint's file-length cap.
}
