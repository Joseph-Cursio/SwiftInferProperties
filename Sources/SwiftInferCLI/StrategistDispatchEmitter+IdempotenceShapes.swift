import Foundation

/// The four idempotence *emit shapes*. `composeIdempotencePass` in
/// `StrategistDispatchEmitter+Templates.swift` stays the dispatcher; the bodies
/// live here because the fourth shape pushed that file past the 400-line cap.
///
/// The shapes are distinguished by what the callee looks like, not by what the
/// law says — the law is `f` applied twice equals `f` applied once in all four:
///
///   - **direct** — `f(f(x)) == f(x)`, for a free / static function.
///   - **mutating** — `var copy = value; copy.f(); copy.f()`.
///   - **self-returning nullary** — `value.f().f() == value.f()`.
///   - **operand** — `a.f(b).f(b) == a.f(b)`, the only two-value shape.
extension StrategistDispatchEmitter {

    /// The plain `f(f(x)) == f(x)` shape — everything that is not a mutating or
    /// self-returning instance method. Split out to keep
    /// `composeIdempotencePass`'s dispatch inside the function-body budget.
    static func composeDirectIdempotencePass(
        functionCall: String,
        recipe: GeneratorRecipe
    ) -> String {
        let oracle = "applyOnce(applyOnce(candidate)) != applyOnce(candidate)"
        let shrink = shrinkableScalarCarriers.contains(recipe.carrierTypeName)
            ? singleShrinkPhase(carrier: recipe.carrierTypeName, oracle: oracle)
            : ""
        let carrier = recipe.carrierTypeName
        return """
        // --- Pass 1: default (strategist-derived generator) ---

        let defaultGenerator: Generator<\(carrier), some SendableSequenceType> =
            \(recipe.expression)

        // Bound once, with an explicit type, and called by name everywhere
        // below. `functionCalls` may be a closure literal — the form a labelled
        // call takes — and applying one inline (`{ … }(value)`) leaves `$0` with
        // nothing to infer from: "cannot infer type of closure parameter '$0'".
        // On a large derived generator the compiler gives up and the run comes
        // back `measured-error: build-failed`. The annotation is the fix; a bare
        // function reference coerces to it unchanged.
        let applyOnce: (\(carrier)) -> \(carrier) = \(functionCall)

        for trial in 0 ..< trials {
            let value = defaultGenerator.run(using: &rng)
            let onceResult = applyOnce(value)
            let twiceResult = applyOnce(onceResult)
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

        \(CollisionPass.unarySweep(
            carrier: recipe.carrierTypeName,
            body: idempotenceCollisionBody()
        ))

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
    static func composeMutatingIdempotencePass(
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
    static func composeSelfReturningIdempotencePass(
        functionCall: String,
        recipe: GeneratorRecipe,
        isComputedProperty: Bool
    ) -> String {
        let methodName = functionCall.split(separator: ".").last.map(String.init) ?? functionCall
        // Accessed, not called — the same bit `composeSelfReturningInvolutionPass` has always
        // consulted, and this composer never did. `FilePath.dirname` is a `public var` and this
        // emitted `value.dirname()`. See `docs/measurements/criterion-a-swift-system.md` §3.
        let accessor = isComputedProperty ? "" : "()"
        return """
        // --- Pass 1: default (strategist-derived generator) ---
        // self-returning instance shape: `value.\(methodName)\(accessor)`
        // chained — applying `\(methodName)` twice equals applying it once.

        let defaultGenerator: Generator<\(recipe.carrierTypeName), some SendableSequenceType> =
            \(recipe.expression)

        for trial in 0 ..< trials {
            let value = defaultGenerator.run(using: &rng)
            let onceResult = value.\(methodName)\(accessor)
            let twiceResult = onceResult.\(methodName)\(accessor)
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

    /// Emit the operand-idempotence shape for a self-returning instance method
    /// that takes one operand: `a.merge(b).merge(b)` must equal `a.merge(b)`.
    ///
    /// Two values per trial, like commutativity — the receiver and the operand.
    /// `functionCall` arrives as the receiver closure `{ $0.merge($1) }`, so it
    /// is applied positionally; it is bound to an explicitly-typed local first
    /// for the same reason `composeDirectIdempotencePass` does it (a closure
    /// literal applied inline leaves `$0` with nothing to infer from).
    ///
    /// **The operand is held FIXED across the two applications.** Redrawing it
    /// would test `a.merge(b).merge(c) == a.merge(b)`, which is not idempotence
    /// and is false for any merge that does anything at all.
    static func composeOperandIdempotencePass(
        functionCall: String,
        recipe: GeneratorRecipe
    ) -> String {
        let carrier = recipe.carrierTypeName
        return """
        // --- Pass 1: default (strategist-derived generator) ---
        // operand-idempotence shape: applying the SAME operand a second time
        // changes nothing — `a.f(b).f(b) == a.f(b)`.

        let defaultGenerator: Generator<\(carrier), some SendableSequenceType> =
            \(recipe.expression)

        let applyOperand: (\(carrier), \(carrier)) -> \(carrier) = \(functionCall)

        for trial in 0 ..< trials {
            let value = defaultGenerator.run(using: &rng)
            let operand = defaultGenerator.run(using: &rng)
            let onceResult = applyOperand(value, operand)
            let twiceResult = applyOperand(onceResult, operand)
            if onceResult != twiceResult {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: \\(value) | operand: \\(operand)")
                print("VERIFY_DEFAULT_FORWARD: \\(onceResult)")
                print("VERIFY_DEFAULT_INVERSE: \\(twiceResult)")
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }
}
