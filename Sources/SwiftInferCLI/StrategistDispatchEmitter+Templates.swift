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
        // V1.60.A — mutating-instance-method shape for OC carriers.
        // The cycle-56 surface (`docs/calibration-cycle-56-findings.md`)
        // showed 5 idempotence picks on OrderedSet<Int> compile-failing
        // with the static-call-of-instance-method shape. New emit shape:
        // `var copy1 = value; copy1.method(); var copy2 = value;
        // copy2.method(); copy2.method(); if copy1 != copy2 { fail }`.
        // The method name is extracted from the functionCall by
        // splitting on `.` and taking the last component.
        if mutatingInstanceCarriers.contains(recipe.carrierTypeName) {
            return composeMutatingIdempotencePass(
                functionCall: functionCall,
                recipe: recipe
            )
        }
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
        "OrderedDictionary<Int, Int>.Elements"
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
    //         (1 value per trial; nonMut(x) == { var c = x; c.mut(); c })

    /// Draws one value, calls the non-mutating function, then mutates
    /// a copy with the mutating counterpart and asserts they agree.
    /// `inputs.functionCalls` carries `[nonMutCall, mutCall]` —
    /// `nonMutCall(x)` produces the non-mutating result;
    /// `mutCall` is invoked via `copy.mutCall()` so the resolver
    /// must produce a bare instance-method name (no receiver, no
    /// argument list).
    static func composeDualStyleConsistencyPass(
        inputs: Inputs,
        recipe: GeneratorRecipe
    ) throws -> String {
        guard inputs.functionCalls.count == 2 else {
            throw VerifyError.unsupportedTemplate(
                template: "dual-style-consistency",
                expected: ["functionCalls must be [nonMutCall, mutMethodName]"]
            )
        }
        let nonMutCall = inputs.functionCalls[0]
        let mutMethodName = inputs.functionCalls[1]
        // V1.61.B — mutating-instance-method shape for OC dual-style.
        // SetAlgebra pairs (union/formUnion etc.) take a SECOND OC
        // value as argument; the v1.48.B shape assumed 0-arg variants
        // (sorted/sort) and doesn't generalize. Cycle-58 OC dual-style
        // picks need 2 values per trial + instance-method shape on
        // both halves: `let nonMut = value.union(other); var copy =
        // value; copy.formUnion(other); assert nonMut == copy`.
        if mutatingInstanceCarriers.contains(recipe.carrierTypeName) {
            return composeMutatingDualStylePass(
                nonMutCall: nonMutCall,
                mutMethodName: mutMethodName,
                recipe: recipe
            )
        }
        return """
        // --- Pass 1: default (strategist-derived generator) ---

        let defaultGenerator: Generator<\(recipe.carrierTypeName), some SendableSequenceType> =
            \(recipe.expression)

        for trial in 0 ..< trials {
            let original = defaultGenerator.run(using: &rng)
            let nonMutResult = \(nonMutCall)(original)
            var mutCopy = original
            mutCopy.\(mutMethodName)()
            if nonMutResult != mutCopy {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: \\(original)")
                print("VERIFY_DEFAULT_FORWARD: \\(nonMutResult)")
                print("VERIFY_DEFAULT_INVERSE: \\(mutCopy)")
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    /// V1.61.B — mutating-instance-method dual-style emit shape for
    /// OC SetAlgebra pairs. Two values per trial; both halves use
    /// instance-method call shape. The non-mutating method name is
    /// extracted from `nonMutCall` by splitting on `.` and taking the
    /// trailing component (e.g. `OrderedSet.union` → `union`); the
    /// `nonMutMethodName` becomes a 1-arg instance call.
    private static func composeMutatingDualStylePass(
        nonMutCall: String,
        mutMethodName: String,
        recipe: GeneratorRecipe
    ) -> String {
        let nonMutMethodName = nonMutCall.split(separator: ".").last.map(String.init) ?? nonMutCall
        return """
        // --- Pass 1: default (strategist-derived generator) ---
        // V1.61.B — mutating-instance-method dual-style shape: assert
        // `value.\(nonMutMethodName)(other)` equals the result of
        // mutating a copy in place via `copy.\(mutMethodName)(other)`.

        let defaultGenerator: Generator<\(recipe.carrierTypeName), some SendableSequenceType> =
            \(recipe.expression)

        for trial in 0 ..< trials {
            let original = defaultGenerator.run(using: &rng)
            let other = defaultGenerator.run(using: &rng)
            let nonMutResult = original.\(nonMutMethodName)(other)
            var mutCopy = original
            mutCopy.\(mutMethodName)(other)
            if nonMutResult != mutCopy {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: (\\(original), \\(other))")
                print("VERIFY_DEFAULT_FORWARD: \\(nonMutResult)")
                print("VERIFY_DEFAULT_INVERSE: \\(mutCopy)")
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    // MARK: - V1.48.A Monotonicity (2 values per trial; a ≤ b → f(a) ≤ f(b))

    /// Draws two values, sorts so `a ≤ b`, applies the function to
    /// each, and asserts `f(a) ≤ f(b)`. The carrier must conform to
    /// `Comparable`; v1.48 trusts the strategist's surface
    /// (Int / String / Bool / fixed-width ints — all Comparable).
    static func composeMonotonicityPass(
        inputs: Inputs,
        recipe: GeneratorRecipe
    ) -> String {
        let functionCall = inputs.functionCalls.first ?? "(missing)"
        return """
        // --- Pass 1: default (strategist-derived generator) ---

        let defaultGenerator: Generator<\(recipe.carrierTypeName), some SendableSequenceType> =
            \(recipe.expression)

        for trial in 0 ..< trials {
            let firstDraw = defaultGenerator.run(using: &rng)
            let secondDraw = defaultGenerator.run(using: &rng)
            let valueA = min(firstDraw, secondDraw)
            let valueB = max(firstDraw, secondDraw)
            let resultA = \(functionCall)(valueA)
            let resultB = \(functionCall)(valueB)
            if resultA > resultB {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: (\\(valueA), \\(valueB))")
                print("VERIFY_DEFAULT_FORWARD: \\(resultA)")
                print("VERIFY_DEFAULT_INVERSE: \\(resultB)")
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }
}
