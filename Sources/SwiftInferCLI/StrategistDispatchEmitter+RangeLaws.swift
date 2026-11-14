import SwiftInferCore

// The range-law composers (#701), in their own file for the reason the sibling
// `+Differential` / `+AlgebraicLaws` files exist: `+AlgebraicLaws` sits within
// a few composers of SwiftLint's 400-line file cap, and splitting is the
// standing remedy here rather than trimming a rationale that records a
// measurement. `empty-range` is dispatched from `algebraicLawPass`;
// `documented-range` from `totalityLawPass`, whose per-parameter operands it shares.
extension StrategistDispatchEmitter {

    // MARK: - Empty range (1 value per trial, passed as both ends; the result is empty)

    /// **The empty range law** — `f(from: v, to: v).isEmpty` for every drawn `v`.
    ///
    /// One value is drawn and passed as BOTH ends, so the recipe is the bound type `T`'s own
    /// and nothing pairs two draws: an empty range is the one range a single value spells.
    /// The check is `.isEmpty`, which every collection the template admits has, so it asks
    /// for no conformance the tool would have to prove — the property that made this law
    /// composable where eight role postconditions were declined.
    ///
    /// **A failure is an assertion, never a trap.** The counterexample prints the INPUT,
    /// the non-empty result as FORWARD and the expectation as INVERSE, the shape
    /// `composeRolePostconditionPass` uses. It deliberately does NOT print
    /// `VERIFY_TRIAL_INPUT` / `VERIFY_TRIAL_CARRIER`: those are totality's markers, and
    /// `VerifyResultParser` reads a trap carrying them as a totality refutation. A trap in
    /// `f(from: v, to: v)` is not a refutation of THIS law, so it stays an `.error`.
    ///
    /// No shrink phase: the counterexample is one value, and the usual failure — a `to:`
    /// the author meant as inclusive — fails at every value, so a smaller one says nothing
    /// the first does not.
    static func composeEmptyRangePass(inputs: Inputs, recipe: GeneratorRecipe) -> String {
        let functionCall = inputs.functionCalls.first ?? "(missing)"
        return """
        // --- Pass 1: default (strategist-derived generator) ---
        // empty range: one value passed as both ends selects nothing, because `to:` is an
        // exclusive end by Swift's convention.

        let defaultGenerator: Generator<\(recipe.carrierTypeName), some SendableSequenceType> =
            \(recipe.expression)

        for trial in 0 ..< trials {
            let value = defaultGenerator.run(using: &rng)
            let result = \(functionCall)(value, value)
            if !result.isEmpty {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: \\(value)")
                print("VERIFY_DEFAULT_FORWARD: \\(result)")
                print("VERIFY_DEFAULT_INVERSE: <empty>")
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }

    // MARK: - Documented range (1 value per parameter, plus the receiver; the result is in range)

    /// **The documented range law** — `(L...U as ClosedRange<Double>).contains(Double(f(x)))`
    /// for every drawn receiver and argument list, with `L` and `U` the literals the doc comment
    /// states.
    ///
    /// The operands are totality's (`totalityOperands`): one generator per parameter, plus the
    /// receiver for an instance member, and the whole entry declines if any one cannot be
    /// derived. That is the operand SHAPE `accept` already writes this law over
    /// (`InteractiveTriage+AcceptTotality.swift`'s `totalityStub` with `.withinRange`) — one draw
    /// per parameter, plus the receiver. **Where the domains differ is narrow, and worth stating
    /// exactly:**
    ///
    /// - **A `String` operand: different domains.** `accept`'s `totalityGenerator` →
    ///   `LiftedTestEmitter.hostileGenerator` draws the kit's hostile `String`, seeded with the
    ///   subject's own literals; verify's `resolveRecipe` takes its raw-type branch and draws the
    ///   kit's edge-biased `String` (`edgeBiasedStringExpression`), never hostile, with no
    ///   subject literals.
    /// - **A `[String]` operand: different domains, and verify's is narrower still.** `accept`
    ///   draws `(hostile String).array(of: 0...8)`, the same seeded hostile elements.
    ///   `resolveRecipe` has no raw type for `[String]`, so it reaches the kit's
    ///   `DerivationStrategist.composedGenerator`, whose leaf for `String` is the PLAIN
    ///   `RawType.generatorExpression`, `Gen<Character>.letterOrNumber.string(of: 0...8)`: its
    ///   elements are alphanumeric only, neither edge-biased nor hostile (the edge bias is applied
    ///   to a top-level `String` carrier alone).
    /// - **Every other raw type (`Int`, `Double`, `Float`, …): the SAME generator.** The kit's
    ///   `hostileGeneratorExpression` and `edgeBiasedGeneratorExpression` both return `nil` for
    ///   anything but `.string`, so `hostileGenerator` falls through `defaultGenerator` to the
    ///   plain `rawType.generatorExpression` — exactly what `resolveRecipe` emits, and no subject
    ///   literal reaches it. A `Double` subject's two runs differ only in seed and trial count.
    /// - **Beyond the parameter draws:** `accept` may construct the receiver from an expression
    ///   where verify derives it, a type outside `RawType` goes through each tool's own
    ///   derivation, and verify runs its Pass 2 edge recipes besides.
    ///
    /// So a checked-in stub failing beside a verify pass is possible: for a `String` or
    /// `[String]` operand the stub can reach an input verify's domain does not (hostile scalars
    /// and the subject's literals for both; for a `[String]`, any whitespace or punctuation at
    /// all, which its verify elements never draw). For a numeric one, look at the seed, the
    /// trial count and the receiver before the generators. Either way it is a
    /// counterexample to read, not a disagreement between the two instruments' laws.
    ///
    /// **The bounds are spliced verbatim, inside `as ClosedRange<Double>`.** Without the
    /// annotation `0 ... 100` infers `ClosedRange<Int>`, and `contains(Double(result))` then
    /// fails to compile. The check is on `Double(result)` so NaN and infinity — a zero
    /// denominator whose guard a mutant removed — fall outside every range; that is the
    /// template's stated reason for reading the result as a `Double`. The bounds are separated
    /// by spaces because `...-1` lexes as one operator, `...-`, and a negative upper bound would
    /// not parse.
    ///
    /// **A failure is an assertion, never a trap**, as for `composeEmptyRangePass`: it prints
    /// the INPUT, the out-of-range result as FORWARD and the range as INVERSE, and none of
    /// totality's `VERIFY_TRIAL_*` markers. An integer subject can trap before the check runs
    /// (a division by zero); that is not a refutation of THIS law, so it stays an `.error`
    /// rather than being read back as a totality counterexample. No shrink phase: the
    /// counterexample may be a tuple of several derived values, and no shrinker covers that.
    ///
    /// **A `Float` result is compared with bounds rounded through `Float`**
    /// (`DocumentedRange.checkedBounds`): widened as-is, a correct clamp to `0.3` returns
    /// 0.30000001192… and would be refuted against the `Double` 0.3. `accept`'s
    /// `LiftedTestEmitter.withinDocumentedRange` spells the bounds the same way, so the two still
    /// state one law.
    ///
    /// Throws `staleIndexEntry` when the range is absent: the composer has no bounds of its own,
    /// and a check with invented bounds would refute or pass code against a contract its author
    /// never wrote. `resolveDocumentedRangeCalls` refuses the same entry first; this guard covers
    /// an `Inputs` built without the column.
    static func composeDocumentedRangePass(inputs: Inputs, recipe: GeneratorRecipe) throws -> String {
        let range = try documentedRange(of: inputs)
        return documentedRangeBody(
            inputs: inputs,
            range: range,
            operands: try totalityOperands(inputs: inputs, recipe: recipe)
        )
    }

    /// Pass 2 for a documented-range entry on the per-parameter operand path, or `nil` to leave
    /// the entry to the generic `edgePassSection`.
    ///
    /// The generic edge pass swaps in an edge recipe for the CARRIER and re-runs the composer.
    /// On the per-parameter path (`usesPerParameterOperands`) `totalityOperands` resolves each
    /// parameter's recipe itself and never reads the carrier's, so that swap changed nothing:
    /// Pass 2 re-drew the ordinary domain and was labelled a clean boundary pass. Here each
    /// parameter's recipe is swapped for its own edge recipe where it has one; a parameter with
    /// none stays ordinary, the mixed-magnitude mitigation `boundarySweep` documents. With no
    /// parameter swapped at all, the zero-trial sentinel says no boundary pass ran.
    static func documentedRangeEdgePassSection(inputs: Inputs, recipe: GeneratorRecipe) throws -> String? {
        guard inputs.template == TemplateName.documentedRange.rawValue,
              usesPerParameterOperands(inputs) else { return nil }
        let range = try documentedRange(of: inputs)
        let operands = try totalityOperands(inputs: inputs, recipe: recipe, leafRecipe: edgeRecipe(from:))
        guard operands.substitutedLeafCount > 0 else { return edgeSentinelSection() }
        let body = documentedRangeBody(inputs: inputs, range: range, operands: operands)
        return edgePassBody(fromDefaultBody: body) ?? edgeSentinelSection()
    }

    private static func documentedRange(of inputs: Inputs) throws -> DocumentedRange {
        guard let range = inputs.documentedRange else {
            throw VerifyError.staleIndexEntry(
                template: TemplateName.documentedRange.rawValue,
                primary: inputs.functionCalls.first ?? "(missing)",
                reason: SwiftInferCommand.Verify.documentedRangeMissingReason
            )
        }
        return range
    }

    private static func documentedRangeBody(
        inputs: Inputs,
        range: DocumentedRange,
        operands: TotalityOperands
    ) -> String {
        let functionCall = inputs.functionCalls.first ?? "(missing)"
        let checked = range.checkedBounds
        let rangeLiteral = "\(checked.lower) ... \(checked.upper)"
        return """
        // --- Pass 1: default (strategist-derived generator) ---
        // documented range: the doc comment states \(range.lower)...\(range.upper), so every result
        // must lie in it. Read as a Double, so NaN and infinity fall outside.

        let documentedRange = (\(rangeLiteral) as ClosedRange<Double>)

        \(operands.declarations)

        for trial in 0 ..< trials {
        \(operands.drawStatements)
            let result = \(functionCall)(\(operands.argumentList))
            if !documentedRange.contains(Double(result)) {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: \\(\(operands.inputExpression))")
                print("VERIFY_DEFAULT_FORWARD: \\(result)")
                print("VERIFY_DEFAULT_INVERSE: <within \(range.lower)...\(range.upper)>")
                exit(1)
            }
        }

        print("VERIFY_DEFAULT_RESULT: PASS")
        print("VERIFY_DEFAULT_TRIALS: \\(trials)")
        """
    }
}
