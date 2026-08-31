import Foundation
import SwiftInferCore

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
//     `git show 31a347a:docs/calibration-cycle-60-monotonicity-investigation.md`.
extension StrategistDispatchEmitter {

    /// V1.69 — carrier type-names whose monotonicity pick is an
    /// *instance method over an index parameter* (`index(after:)` /
    /// `index(before:)`) rather than a function over the carrier value.
    /// Each carrier here is an OrderedCollections view with `Index ==
    /// Int`; `composeInstanceMethodMonotonicityPass` emits the
    /// receiver-and-index shape for them. Synced with
    /// `StrategistDispatchEmitter.curatedOCRecipe` — every carrier in
    /// this set must have a curated OC recipe.
    /// Carriers whose `index(after:)` / `index(before:)` the receiver-and-index shape can
    /// verify. Each is a `RandomAccessCollection` with `Index == Int`.
    ///
    /// ⚠ **SPELLED WITHOUT GENERIC ARGUMENTS, and the previous spelling made every entry
    /// UNREACHABLE.** This list read `OrderedSet<Int>`,
    /// `OrderedDictionary<Int, Int>.Elements` and three more fully-specialised forms, while
    /// discovery records a carrier **unspecialised** — `OrderedSet`,
    /// `OrderedDictionary.Elements`. The two spellings never met, so the instance path could
    /// not fire on any real row and every one of them fell through to the value path, which
    /// emits a STATIC call on an instance method.
    ///
    /// **Measured on `swift-collections` @ `899809d3`**: 31 of 64 `monotonicity` rows
    /// declined `instance-method-shape-not-supported` — the largest single blocker — and
    /// **12 of those are carriers this list already names**. The compiler's words:
    /// `instance member 'index' cannot be used on type 'Deque<<<hole>>>'`.
    ///
    /// **The emitter tests were green throughout**, because they construct carriers with the
    /// specialised spelling the list used. A test-versus-production spelling mismatch is
    /// exactly the shape of the `Swift.String` leaf-recognition defect fixed 2026-08-25.
    /// ⚠ **Spelled SPECIALISED while a discovery row's carrier is spelled UNSPECIALISED
    /// (`OrderedSet`, not `OrderedSet<Int>`) — a real mismatch, and NOT what blocks these
    /// rows.** Normalising the two was built, A/B'd on `swift-collections` @ `899809d3` and
    /// **reverted: 0 rows moved.** The check below reads `recipe.carrierTypeName`, and for
    /// `index(before:)` that is the PARAMETER type — `Int` — so it can never name a
    /// collection at any spelling. See `docs/measurements/instance-method-shape-census.md`.
    ///
    /// `MonotonicityOCEmitterTests` iterates this set and requires every entry to resolve a
    /// curated OC recipe, which the bare spelling does not — so a future fix must move the
    /// recipe, not this list.
    /// The same carriers keyed by their bare, unspecialised names — what a discovery row's
    /// carrier looks like. **Derived, never written out**, so the two cannot drift.
    static let monotonicityInstanceCarrierKeys: Set<String> =
        Set(monotonicityInstanceCarriers.map(unspecialised))

    /// Whether the receiver-and-index shape applies, on either spelling. **Exact membership is
    /// what the emitter tests exercise (they supply `OrderedSet<Int>`); the bare form is what
    /// production supplies.** Both must match, which is the whole of the V1.69 path's
    /// unreachability — see `instance-method-shape-census.md` §7.
    static func isMonotonicityInstanceCarrier(_ carrier: String) -> Bool {
        monotonicityInstanceCarrierKeys.contains(unspecialised(carrier))
    }

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

    /// Value-monotonicity domains the strategist can generate AND order with
    /// `min`/`max` — the Comparable scalar types. A domain outside this set is
    /// treated as Comparable only when its indexed shape declares the
    /// conformance (see `isComparableMonotonicityDomain`).
    ///
    /// Stated as the shrinkable numeric scalars plus the three Comparable
    /// non-numeric scalars, which is exactly how it relates to
    /// `shrinkableMonotonicityCarriers`: same set, minus the types that have no
    /// `shrink(towards: 0)`. Previously both were spelled out longhand and had to
    /// be kept in step by hand.
    static let comparableMonotonicityDomains: Set<String> =
        FixedWidthIntegerNames.withBinaryFloats.union(["String", "Bool", "Character"])

    /// Whether the value-monotonicity domain is orderable by `min`/`max`: a
    /// known Comparable scalar, or a type whose indexed shape lists `Comparable`
    /// in its inherited types (e.g. `enum Confidence: Int, Comparable`). A
    /// custom type without a captured `Comparable` conformance is treated as
    /// non-orderable — the conservative, build-safe choice.
    static func isComparableMonotonicityDomain(_ domain: String, inputs: Inputs) -> Bool {
        if comparableMonotonicityDomains.contains(domain) { return true }
        if inputs.allShapes[domain]?.inheritedTypes.contains("Comparable") == true { return true }
        if inputs.typeShape?.name == domain,
           inputs.typeShape?.inheritedTypes.contains("Comparable") == true {
            return true
        }
        return false
    }

    /// Pre-flight for value monotonicity: the `min`/`max` ordering requires a
    /// Comparable domain, so throw (→ architectural-coverage-pending, the
    /// doomed `swift build` skipped) when the domain isn't Comparable.
    /// Instance-method monotonicity carriers order *indices* (`Int`), not the
    /// carrier value, so they're exempt.
    static func requireComparableMonotonicityDomain(
        inputs: Inputs,
        recipe: GeneratorRecipe
    ) throws {
        let domain = recipe.carrierTypeName
        guard !isMonotonicityInstanceCarrier(domain) else { return }
        guard isComparableMonotonicityDomain(domain, inputs: inputs) else {
            throw VerifyError.monotonicityDomainNotComparable(domain: domain)
        }
    }

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
    /// method — see
    /// `git show 31a347a:docs/calibration-cycle-60-monotonicity-investigation.md`).
    /// Those carriers route to `composeInstanceMethodMonotonicityPass`.
    static func composeMonotonicityPass(
        inputs: Inputs,
        recipe: GeneratorRecipe
    ) -> String {
        let functionCall = inputs.functionCalls.first ?? "(missing)"
        if isMonotonicityInstanceCarrier(recipe.carrierTypeName) {
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
    /// Derived as the fixed-width integers plus the binary floats, so this list
    /// cannot drift out of step with `shrinkableScalarCarriers` (the integers) —
    /// the two differ by exactly `Double`/`Float`, and now say so structurally.
    static let shrinkableMonotonicityCarriers: Set<String> = FixedWidthIntegerNames.withBinaryFloats

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
    /// (`git show 31a347a:docs/calibration-cycle-60-monotonicity-investigation.md`)
    /// showed
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
    /// ⚠ **The reasoning that used to stand here — *the curated OC recipes always produce
    /// non-empty collections, so no empty-collection guard [is] needed* — was true of five
    /// curated carriers and EXPIRES the moment that list widens**, which is the first thing
    /// any fix to `instance-method-shape-not-supported` will do. The emitted loop now
    /// guards; see `docs/measurements/instance-method-shape-census.md` §5.
    private static func composeInstanceMethodMonotonicityPass(
        functionCalls: [String],
        recipe: GeneratorRecipe
    ) -> String {
        let primaryName = functionCalls.count >= 2 ? functionCalls[1] : (functionCalls.first ?? "(missing)")
        // **Read the method name off the RAW call, never off `functionCalls.first`.** Since
        // the labelled-call fix, element 0 is the labelled form and may be a closure literal
        // (`{ Deque.index(after: $0) }`), which `split(".").last` answers nonsense for. The
        // raw reference is element 2; falling back to element 0 keeps a two-element caller
        // (a labelless subject, where the two forms are identical) working unchanged.
        let rawCall = functionCalls.count >= 3
            ? functionCalls[2]
            : (functionCalls.first ?? "(missing)")
        let methodName = rawCall.split(separator: ".").last.map(String.init) ?? rawCall
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
        return instanceMethodMonotonicityBody(
            methodName: methodName, argLabel: argLabel, indexDomain: indexDomain, recipe: recipe
        )
    }

    /// The emitted body, split out so the composer above stays inside the body-length cap.
    /// **Split when the empty-collection guard pushed it over**, rather than shaving the
    /// guard's comment — the seam is clean and the reasoning is what a later reader needs.
    private static func instanceMethodMonotonicityBody(
        methodName: String,
        argLabel: String,
        indexDomain: String,
        recipe: GeneratorRecipe
    ) -> String {
        """
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
            // An EMPTY receiver makes the index domain below an invalid range — `0 ... -1`
            // for `index(after:)`, `1 ... 0` for `index(before:)` — which TRAPS at run time
            // rather than failing a law. The V1.69 curated carriers could not produce one,
            // and the comment saying so was the only thing standing between this and a
            // trap; it stopped being true the moment carrier matching widened.
            //
            // `count == 1` is fine and deliberately admitted: the domain is `0 ... 0` or
            // `1 ... 1`, both valid, and drawing the same index twice makes the comparison
            // trivially true rather than wrong.
            guard !receiver.isEmpty else { continue }
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
