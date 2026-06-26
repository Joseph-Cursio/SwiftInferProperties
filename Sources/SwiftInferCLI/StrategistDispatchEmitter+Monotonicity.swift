import Foundation

// V1.48.A / V1.69 — monotonicity Pass 1 composers for the
// strategist-routed emitter. Extracted from
// `StrategistDispatchEmitter+Templates.swift` in V1.69 when the OC
// instance-method rework pushed that file over SwiftLint's
// file-length cap.
//
// Two shapes:
//   - **value monotonicity** (`composeMonotonicityPass` else-branch) —
//     the v1.48 shape for `Comparable` carriers (Int / String / Bool /
//     fixed-width ints): draw two carrier values, order with
//     `min`/`max`, assert `f(a) ≤ f(b)`.
//   - **instance-method monotonicity** (`composeInstanceMethodMonotonicityPass`)
//     — V1.69 shape for OC collection carriers whose monotonicity pick
//     is `index(after:)` / `index(before:)`: the property is over the
//     *index* parameter (`Int`), not the carrier. See
//     `docs/calibration-cycle-60-monotonicity-investigation.md`.
extension StrategistDispatchEmitter {

    /// V1.69 — carrier type-names whose monotonicity pick is an
    /// *instance method over an index parameter* (`index(after:)` /
    /// `index(before:)`) rather than a function over the carrier value.
    /// Each carrier here is an OrderedCollections view with `Index ==
    /// Int`; `composeInstanceMethodMonotonicityPass` emits the
    /// receiver-and-index shape for them. Synced with
    /// `StrategistDispatchEmitter.curatedOCRecipe` — every carrier in
    /// this set must have a curated OC recipe.
    static let monotonicityInstanceCarriers: Set<String> = [
        "OrderedSet<Int>",
        "OrderedDictionary<Int, Int>.Elements",
        // V1.69 — the three nested-OC view carriers scaffolded in
        // V1.69.B. Each is a RandomAccessCollection with `Index == Int`,
        // so the receiver-and-index emit shape applies unchanged.
        "OrderedSet<Int>.SubSequence",
        "OrderedDictionary<Int, Int>.Values",
        "OrderedDictionary<Int, Int>.Elements.SubSequence"
    ]

    /// Draws two values, sorts so `a ≤ b`, applies the function to
    /// each, and asserts `f(a) ≤ f(b)`. The carrier must conform to
    /// `Comparable`; v1.48 trusts the strategist's surface
    /// (Int / String / Bool / fixed-width ints — all Comparable).
    ///
    /// V1.69 — OC collection carriers (`OrderedSet<Int>` etc.) carry
    /// monotonicity over an *index* parameter via an instance method,
    /// not over the carrier value. The v1.48 `min`/`max`-on-carrier +
    /// static-call shape hard-fails on those (the carrier isn't
    /// `Comparable` *and* `Carrier.index(value)` mismodels the instance
    /// method — see `docs/calibration-cycle-60-monotonicity-investigation.md`).
    /// Those carriers route to `composeInstanceMethodMonotonicityPass`.
    static func composeMonotonicityPass(
        inputs: Inputs,
        recipe: GeneratorRecipe
    ) -> String {
        let functionCall = inputs.functionCalls.first ?? "(missing)"
        if monotonicityInstanceCarriers.contains(recipe.carrierTypeName) {
            return composeInstanceMethodMonotonicityPass(
                functionCalls: inputs.functionCalls,
                recipe: recipe
            )
        }
        // v1.141: shrink only when the carrier is a numeric type with a
        // `shrink(towards: 0)` (fixed-width ints, Double/Float). String / Bool
        // monotonicity carriers degrade gracefully — first failure reported.
        let shrink = shrinkableMonotonicityCarriers.contains(recipe.carrierTypeName)
            ? monotonicityShrinkPhase(carrier: recipe.carrierTypeName, functionCall: functionCall)
            : ""
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
        \(shrink)
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    /// v1.141 — carrier type-names whose monotonicity value can be shrunk via
    /// `shrink(towards: 0)` (fixed-width integers + binary floats). Other
    /// value-monotonicity carriers (`String`, `Bool`) degrade gracefully.
    static let shrinkableMonotonicityCarriers: Set<String> = [
        "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Double", "Float"
    ]

    /// v1.141 shrink phase for value monotonicity over a shrinkable scalar
    /// carrier: shrink each of the ordered pair toward 0, re-`min`/`max`-ing in
    /// the oracle so a shrunk candidate stays a genuine `f(lo) > f(hi)`
    /// violation, to a fixpoint.
    private static func monotonicityShrinkPhase(carrier: String, functionCall: String) -> String {
        """
        // --- shrink phase (v1.141): minimize the failing pair ---
                func monotonicityFails(_ xValue: \(carrier), _ yValue: \(carrier)) -> Bool {
                    \(functionCall)(Swift.min(xValue, yValue)) > \(functionCall)(Swift.max(xValue, yValue))
                }
                var shrunkA = valueA
                var shrunkB = valueB
                var shrinkSteps = 0
                shrinkLoop: while shrinkSteps < 1000 {
                    for part in shrunkA.shrink(towards: 0) where monotonicityFails(part, shrunkB) {
                        shrunkA = part; shrinkSteps += 1; continue shrinkLoop
                    }
                    for part in shrunkB.shrink(towards: 0) where monotonicityFails(shrunkA, part) {
                        shrunkB = part; shrinkSteps += 1; continue shrinkLoop
                    }
                    break
                }
                print("VERIFY_DEFAULT_SHRUNK: (\\(Swift.min(shrunkA, shrunkB)), \\(Swift.max(shrunkA, shrunkB)))")
                print("VERIFY_SHRINK_STEPS: \\(shrinkSteps)")
        """
    }

    /// V1.69 — instance-method monotonicity emit shape for OC collection
    /// carriers. The monotonicity property for `index(after:)` /
    /// `index(before:)` is over the *index* parameter — an `Int` for
    /// every curated OC carrier (all have `Index == Int`) — not over the
    /// carrier value. The cycle-60 investigation
    /// (`docs/calibration-cycle-60-monotonicity-investigation.md`) showed
    /// the v1.48 `min`/`max`-on-carrier + static-call shape hard-fails
    /// with two co-occurring bugs: the carrier isn't `Comparable`, and
    /// `Carrier.index(value)` mismodels the instance method.
    ///
    /// New shape, per trial: draw a receiver collection from the curated
    /// OC generator, draw two valid indices from the receiver's own
    /// index range, order the *indices* with `min`/`max` (they're `Int`
    /// — `Comparable` by construction), then assert
    /// `receiver.index(after: lo) <= receiver.index(after: hi)`.
    ///
    /// `functionCalls` is `[renderedCall, primaryFunctionName]` — the
    /// second element (e.g. `"index(after:)"`) carries the
    /// labeled-argument name the static `renderedCall` dropped. The
    /// curated OC recipes always produce non-empty (4-element)
    /// collections, so both index domains below are non-empty
    /// `ClosedRange<Int>`s — no empty-collection guard needed.
    private static func composeInstanceMethodMonotonicityPass(
        functionCalls: [String],
        recipe: GeneratorRecipe
    ) -> String {
        let renderedCall = functionCalls.first ?? "(missing)"
        let methodName = renderedCall.split(separator: ".").last.map(String.init) ?? renderedCall
        let primaryName = functionCalls.count >= 2 ? functionCalls[1] : renderedCall
        // `index(before:)` requires an input index strictly greater than
        // `startIndex`; `index(after:)` one strictly less than
        // `endIndex`. Both domains are `ClosedRange<Int>` so the single
        // `Gen<Int>.int(in:)` overload the curated OC recipes already
        // use covers them.
        let isBefore = primaryName.contains("(before:)")
        let argLabel = isBefore ? "before" : "after"
        let indexDomain = isBefore
            ? "(receiver.startIndex + 1) ... receiver.endIndex"
            : "receiver.startIndex ... (receiver.endIndex - 1)"
        return """
        // --- Pass 1: default (strategist-derived generator) ---
        // V1.69 — instance-method monotonicity: draw a receiver
        // collection, draw two valid indices from its own index range,
        // order the *indices* (Int — Comparable), assert
        // `receiver.\(methodName)(\(argLabel):)` is monotonic over them.
        // No carrier `Comparable` requirement.

        let defaultGenerator: Generator<\(recipe.carrierTypeName), some SendableSequenceType> =
            \(recipe.expression)

        for trial in 0 ..< trials {
            let receiver = defaultGenerator.run(using: &rng)
            let indexGenerator: Generator<Int, some SendableSequenceType> =
                Gen<Int>.int(in: \(indexDomain))
            let firstIndex = indexGenerator.run(using: &rng)
            let secondIndex = indexGenerator.run(using: &rng)
            let lowerIndex = min(firstIndex, secondIndex)
            let upperIndex = max(firstIndex, secondIndex)
            let resultA = receiver.\(methodName)(\(argLabel): lowerIndex)
            let resultB = receiver.\(methodName)(\(argLabel): upperIndex)
            if resultA > resultB {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: (\\(lowerIndex), \\(upperIndex))")
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
