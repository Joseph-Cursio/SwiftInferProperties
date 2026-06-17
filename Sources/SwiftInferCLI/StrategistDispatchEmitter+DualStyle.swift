import Foundation

// V1.48.A dual-style-consistency Pass 1 composers for the strategist-
// routed emitter, extracted from `StrategistDispatchEmitter+Templates.swift`
// so that file stays under SwiftLint's file-length cap (mirrors the
// earlier `+Monotonicity` extraction). The property:
// `nonMut(x) == { var c = x; c.mut(); c }`.
extension StrategistDispatchEmitter {

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
        let nonMutResultExpr = dualStyleNonMutatingCallExpression(nonMutCall)
        return """
        // --- Pass 1: default (strategist-derived generator) ---

        let defaultGenerator: Generator<\(recipe.carrierTypeName), some SendableSequenceType> =
            \(recipe.expression)

        for trial in 0 ..< trials {
            let original = defaultGenerator.run(using: &rng)
            let nonMutResult = \(nonMutResultExpr)
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

    /// Render the non-mutating half of a (single-value, non-OC) dual-style
    /// check against `original`. The pair resolver qualifies a member as
    /// `Type.method`; invoking that as `Type.method(original)` yields the
    /// curried *unbound* method (`(Type) -> () -> U`), not a value, so a
    /// custom-carrier instance method must be called as `original.method()`.
    /// A bare, dot-free name is a free/static function (the V1.49.F
    /// preamble-injection shape used by `VerifyPipelineLiftedIntegrationTests`)
    /// and stays `name(original)`. Non-OC dual-style pairs are the 0-arg
    /// Collection family (`sorted`/`reversed`/`shuffled`), so the bare
    /// `original.method()` call is always argument-free here; the 1-arg
    /// SetAlgebra pairs route through `composeMutatingDualStylePass` instead.
    static func dualStyleNonMutatingCallExpression(_ nonMutCall: String) -> String {
        guard nonMutCall.contains(".") else { return "\(nonMutCall)(original)" }
        let method = nonMutCall.split(separator: ".").last.map(String.init) ?? nonMutCall
        return "original.\(method)()"
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
        // Cycle 149 (Lever C-1) — the OrderedDictionary `merge` /
        // `merging` pair takes a required `uniquingKeysWith:` closure that
        // the SetAlgebra pairs (`union(_:)` etc.) don't. Both halves use
        // the SAME keep-new closure, so the dual-style equivalence still
        // holds (the closure is a pure conflict policy, identical on each
        // side). The SetAlgebra ops get an empty suffix → unchanged shape.
        let trailing = dualStyleTrailingArgument(forMutating: mutMethodName)
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
            let nonMutResult = original.\(nonMutMethodName)(other\(trailing))
            var mutCopy = original
            mutCopy.\(mutMethodName)(other\(trailing))
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

    /// Cycle 149 (Lever C-1) — trailing call argument(s) a curated
    /// mutating dual-style method needs beyond `(other)`, keyed by the
    /// bare mutating name. Only the OrderedDictionary `merge`/`merging`
    /// family needs one: a keep-new `uniquingKeysWith:` conflict closure
    /// applied identically to both halves, so the equivalence holds.
    static func dualStyleTrailingArgument(forMutating mutMethodName: String) -> String {
        mutMethodName == "merge" ? ", uniquingKeysWith: { (_, new) in new }" : ""
    }
}
