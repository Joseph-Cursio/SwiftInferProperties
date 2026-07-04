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

    // MARK: - Idempotence (1 value per trial; f(f(x)) == f(x))

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
        let oracle = "\(functionCall)(\(functionCall)(candidate)) != \(functionCall)(candidate)"
        let shrink = shrinkableScalarCarriers.contains(recipe.carrierTypeName)
            ? singleShrinkPhase(carrier: recipe.carrierTypeName, oracle: oracle)
            : ""
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
        \(shrink)
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    /// V1.60.A — set of carrier type-names that trigger the
    /// mutating-instance-method emit shape. Each carrier in this set
    /// has its idempotence test emitted as `var copy = value;
    /// copy.method()` rather than `Type.method(value)`. Synced with
    /// `StrategistDispatchEmitter.curatedOCRecipe`'s curated carriers.
    /// V1.62.A — added `OrderedSet<Int>.UnorderedView` (8 cycle-27
    /// dual-style picks).
    static let mutatingInstanceCarriers: Set<String> = [
        "OrderedSet<Int>",
        "OrderedSet<Int>.UnorderedView",
        // V1.63.A — OD.Elements (key-value-pair view) is a
        // MutableCollection with `sort()` etc. Gate it for V1.60.A's
        // mutating-instance idempotence emission.
        "OrderedDictionary<Int, Int>.Elements",
        // Cycle 149 (Lever C-1) — the bare dictionary; `merge` (dual-style
        // mutating side) and `sort()` (idempotence) are mutating instance
        // methods, so they need the `var copy; copy.method()` shape.
        "OrderedDictionary<Int, Int>"
    ]

    /// V1.60.A — emit the mutating-instance-method idempotence shape.
    /// Splits `functionCall` (e.g. `"OrderedSet.sort"`) on `.` and
    /// takes the trailing component as the method name. Operator-named
    /// functions (`(+)`-style) aren't expected in this code path —
    /// mutating instance methods don't have operator spellings — but
    /// would fall through to the static shape if encountered.
    private static func composeMutatingIdempotencePass(
        functionCall: String,
        recipe: GeneratorRecipe
    ) -> String {
        let methodName = functionCall.split(separator: ".").last.map(String.init) ?? functionCall
        return """
        // --- Pass 1: default (strategist-derived generator) ---
        // V1.60.A — mutating-instance-method shape: apply `\(methodName)`
        // once on `onceCopy` and twice on `twiceCopy`; assert equal.

        let defaultGenerator: Generator<\(recipe.carrierTypeName), some SendableSequenceType> =
            \(recipe.expression)

        for trial in 0 ..< trials {
            let value = defaultGenerator.run(using: &rng)
            var onceCopy = value
            onceCopy.\(methodName)()
            var twiceCopy = value
            twiceCopy.\(methodName)()
            twiceCopy.\(methodName)()
            if onceCopy != twiceCopy {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: \\(value)")
                print("VERIFY_DEFAULT_FORWARD: \\(onceCopy)")
                print("VERIFY_DEFAULT_INVERSE: \\(twiceCopy)")
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    /// Emit the non-mutating self-returning instance-method idempotence
    /// shape: chain the method on the receiver — `value.method().method()`
    /// must equal `value.method()`. The method name is extracted from
    /// `functionCall` the same way as the mutating shape. Only reached for
    /// nullary instance methods whose return type is the carrier itself
    /// (`inputs.returnsSelfType`), so the second `.method()` type-checks.
    private static func composeSelfReturningIdempotencePass(
        functionCall: String,
        recipe: GeneratorRecipe
    ) -> String {
        let methodName = functionCall.split(separator: ".").last.map(String.init) ?? functionCall
        return """
        // --- Pass 1: default (strategist-derived generator) ---
        // self-returning instance-method shape: `value.\(methodName)()`
        // chained — applying `\(methodName)` twice equals applying it once.

        let defaultGenerator: Generator<\(recipe.carrierTypeName), some SendableSequenceType> =
            \(recipe.expression)

        for trial in 0 ..< trials {
            let value = defaultGenerator.run(using: &rng)
            let onceResult = value.\(methodName)()
            let twiceResult = onceResult.\(methodName)()
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
