import Foundation
import Testing

@testable import SwiftInferCore

@Suite("DocstringAdvisor — a docstring earns its place only as a reference definition")
struct DocstringAdvisorTests {

    // MARK: - The contract gate

    @Test("a narrating docstring is not a contract and yields no advisory")
    func narrationIsFiltered() {
        // Only red herrings proposed, but the doc merely says why it exists.
        let suggestions = [suggestion(template: "associativity"), suggestion(template: "commutativity")]
        let advisory = DocstringAdvisor.advisory(
            forFunctionWith: "A convenience helper used by the ranking loop.",
            suggestions: suggestions
        )
        #expect(advisory == nil)
    }

    @Test("a nil docstring yields no advisory")
    func noDocIsFiltered() {
        #expect(DocstringAdvisor.advisory(forFunctionWith: nil, suggestions: []) == nil)
    }

    @Test("a checkable claim about the result passes the contract gate")
    func contractGateAcceptsClaims() {
        #expect(DocstringAdvisor.isContract("Returns the nearest multiple of 5; ties round upward."))
        #expect(DocstringAdvisor.isContract("Capped at the ceiling and never negative."))
        #expect(DocstringAdvisor.isContract("A folder name is valid when it is non-empty and contains no slash."))
        #expect(!DocstringAdvisor.isContract("A helper used by the retry loop."))
        #expect(!DocstringAdvisor.isContract("Convenience wrapper. See also the sync path."))
    }

    /// **The gate matched inside words**, so `"reaches"` was read as the quantifier `each` and
    /// `"whenever"` as `never`. Measured over 2 856 documented functions: 110 admitted on a
    /// match like that (SwiftInferProperties#437).
    @Test("a cue inside a longer word is not a cue", arguments: [
        "The shortest hop distance, or nil when it reaches none.",
        "Shown whenever the message is set.",
        "It swaps the selected element, which reorders the tail."
    ])
    func aSubstringMatchIsNotAContract(doc: String) {
        #expect(DocstringAdvisor.isContract(doc) == false)
    }

    /// Code spans are identifiers the docstring is **citing**, not verbs it is using — and
    /// dropping them is what makes the transformation family usable: `resolve` appears in
    /// `GeneratorResolver` far more often than as a claim.
    @Test func aCueInsideACodeSpanIsNotACue() {
        #expect(DocstringAdvisor.isContract("Lint pass — pulled out of `resolveFunctionCalls`.") == false)
        #expect(DocstringAdvisor.isContract("Resolve one generator per parameter type.") == true)
    }

    /// The family the list was missing. `globPatternToRegex` states its contract in its first
    /// sentence and matched none of the previous 59 cues.
    @Test("the transformation family is recognised", arguments: [
        "Translate this glob pattern into an anchored regular-expression string.",
        "Extracts the base type name from a call expression.",
        "Strip a single generic-parameter list from a textual type name.",
        "Splits a camelCase name into its constituent words.",
        "Escape a string for safe inclusion as a Swift string literal.",
        "Render SVG from a pre-computed sequence layout."
    ])
    func transformationVerbsAreContracts(doc: String) {
        #expect(DocstringAdvisor.isContract(doc))
    }

    /// `wrap` is deliberately absent from the family: it would match `"Convenience wrapper"`,
    /// which the narration test above requires this gate to reject.
    @Test func wrapIsNotInTheFamily() {
        #expect(DocstringAdvisor.isContract("Convenience wrapper. See also the sync path.") == false)
    }

    // MARK: - Path 1: a predicate law owes a reference definition

    @Test("a predicate law pulls the docstring in as its reference definition")
    func predicatePullsDefinition() {
        let advisory = DocstringAdvisor.advisory(
            forFunctionWith: "A folder name is valid when it is non-empty and contains no slash.",
            suggestions: [suggestion(template: "predicate")]
        )
        guard case let .referenceDefinition(reference) = advisory else {
            Issue.record("expected .referenceDefinition, got \(String(describing: advisory))")
            return
        }
        #expect(reference.template == "predicate")
        #expect(reference.fromLiftedTest == false)
        #expect(reference.docComment.contains("non-empty"))
    }

    // MARK: - Path 2: a lifted example test needs the sentence it generalizes

    @Test("a law lifted from an example test attaches the docstring as the definition it generalizes")
    func liftedTestPullsDefinition() {
        let advisory = DocstringAdvisor.advisory(
            forFunctionWith: "Returns the nearest multiple of 5; ties round upward.",
            suggestions: [lifted(template: "idempotence")]
        )
        guard case let .referenceDefinition(reference) = advisory else {
            Issue.record("expected .referenceDefinition, got \(String(describing: advisory))")
            return
        }
        #expect(reference.template == "idempotence")
        #expect(reference.fromLiftedTest == true)
    }

    @Test("a role-entailed predicate outranks a lifted test when both are present")
    func predicateOutranksLifted() {
        let advisory = DocstringAdvisor.advisory(
            forFunctionWith: "A folder name is valid when it is non-empty.",
            suggestions: [lifted(template: "idempotence"), suggestion(template: "predicate")]
        )
        guard case let .referenceDefinition(reference) = advisory else {
            Issue.record("expected .referenceDefinition")
            return
        }
        #expect(reference.template == "predicate")
        #expect(reference.fromLiftedTest == false)
    }

    // MARK: - Path 3: nothing role-entailed survived → the sentence is the law

    @Test("only refutable-but-not-role-entailed red herrings → the docstring is the fallback contract")
    func redHerringsFallBackToContract() {
        // backoffDelay's shape: (Int, Int) -> Int matches associativity + commutativity,
        // neither of which a correct capped-backoff owes.
        let advisory = DocstringAdvisor.advisory(
            forFunctionWith: "Capped at the ceiling and never negative.",
            suggestions: [suggestion(template: "associativity"), suggestion(template: "commutativity")]
        )
        guard case let .fallbackContract(contract) = advisory else {
            Issue.record("expected .fallbackContract, got \(String(describing: advisory))")
            return
        }
        #expect(contract.redHerrings == ["associativity", "commutativity"])
        #expect(contract.docComment.contains("never negative"))
    }

    @Test("only a determinism tautology proposed → the docstring is the fallback contract with no red herrings")
    func determinismFallsBackToContract() {
        let advisory = DocstringAdvisor.advisory(
            forFunctionWith: "Returns the nearest multiple of 5.",
            suggestions: [suggestion(template: "determinism")]
        )
        guard case let .fallbackContract(contract) = advisory else {
            Issue.record("expected .fallbackContract")
            return
        }
        #expect(contract.redHerrings.isEmpty)
    }

    @Test("no suggestions at all + a contract doc → fallback contract")
    func emptySuggestionsFallBack() {
        let advisory = DocstringAdvisor.advisory(
            forFunctionWith: "Returns the nearest multiple of 5.",
            suggestions: []
        )
        guard case .fallbackContract = advisory else {
            Issue.record("expected .fallbackContract")
            return
        }
    }

    // MARK: - Path 4: a self-contained role-entailed law already serves it

    @Test("a comparator gets the ordering-key reference definition — the SWO law can't say WHICH ordering")
    func comparatorGetsOrderingKeyDefinition() {
        // The strict-weak-ordering law verifies validity, not the intended key
        // (name length vs lexicographic both pass it). The docstring states the
        // key, so the ordering-key oracle rides alongside the SWO law.
        let advisory = DocstringAdvisor.advisory(
            forFunctionWith: "Orders widgets rank-first, then by name ascending.",
            suggestions: [suggestion(template: "comparator")]
        )
        guard case let .referenceDefinition(reference) = advisory else {
            Issue.record("expected .referenceDefinition, got \(String(describing: advisory))")
            return
        }
        #expect(reference.template == "comparator")
        #expect(reference.fromLiftedTest == false)
    }

    @Test("a partition's tiling is self-contained — no advisory")
    func partitionNeedsNoDocstring() {
        let advisory = DocstringAdvisor.advisory(
            forFunctionWith: "Splits the range into non-overlapping tiles that cover the whole.",
            suggestions: [suggestion(template: "partition")]
        )
        #expect(advisory == nil)
    }

    // MARK: - Path 4: owed, but unreachable by realistic input

    /// **`input-totality` fires on every interpretation verb — that is its trigger — so the whole
    /// parse / decode / read family used to reach the "already served, say nothing" arm**
    /// (SwiftInferProperties#420). Its law is *does not trap*, and its own caveats say a realistic
    /// generator will never find a counterexample; that discharges nothing a docstring claims.
    ///
    /// Measured over SwiftMarkdownWiki: three subjects with contract-cue docstrings, all three
    /// suppressed, and one of the suppressed sentences became a law that found a live bug.
    @Test("an input-totality law does not discharge the docstring — the sentence rides alongside")
    func inputTotalityYieldsAComplementaryContract() {
        let advisory = DocstringAdvisor.advisory(
            forFunctionWith: "Parses all wikilink references from raw Markdown source, in document order.",
            suggestions: [suggestion(template: "input-totality")]
        )
        guard case let .complementaryContract(contract) = advisory else {
            Issue.record("expected .complementaryContract, got \(String(describing: advisory))")
            return
        }
        #expect(contract.servedBy == ["input-totality"])
        #expect(contract.docComment.contains("document order"))
    }

    /// **The arm is about what the reader was handed, not about the docstring.** A function that
    /// also gets a self-contained role-entailed law HAS been served, so the sentence stays out —
    /// which is arm 5's original premise, still correct where it applies.
    @Test("a self-contained law alongside input-totality still suppresses the docstring")
    func aReachableRoleEntailedLawStillSuppresses() {
        let advisory = DocstringAdvisor.advisory(
            forFunctionWith: "Parses all wikilink references from raw Markdown source, in document order.",
            suggestions: [suggestion(template: "input-totality"), suggestion(template: "partition")]
        )
        #expect(advisory == nil)
    }

    /// `normal-form` is the neighbouring candidate and is deliberately NOT treated as unreachable:
    /// `print(parse(print(parse(s)))) == print(parse(s))` is checked by ordinary input and does
    /// constrain what the parse means. Widening the set on no evidence is the mistake this file
    /// keeps recording.
    @Test("normal-form is reachable, so it still serves the function on its own")
    func normalFormIsNotTreatedAsUnreachable() {
        let advisory = DocstringAdvisor.advisory(
            forFunctionWith: "Parses the document and returns the fields it declares.",
            suggestions: [suggestion(template: "normal-form")]
        )
        #expect(advisory == nil)
    }

    /// Arm 3 still wins when nothing role-entailed fired at all — the empty-`serving` case must
    /// not fall through to the new arm, which would call an unserved function served.
    @Test("no role-entailed law at all is still the fallback contract, not the complementary one")
    func nothingRoleEntailedStillFallsBack() {
        let advisory = DocstringAdvisor.advisory(
            forFunctionWith: "Returns the nearest multiple of 5; ties round upward.",
            suggestions: [suggestion(template: "monotonicity")]
        )
        guard case .fallbackContract = advisory else {
            Issue.record("expected .fallbackContract, got \(String(describing: advisory))")
            return
        }
    }

    // MARK: - Fixtures

    private func suggestion(template: String, canonical: String = "x") -> Suggestion {
        let evidence = Evidence(
            displayName: "f(_:)",
            signature: "(Int) -> Int",
            location: SourceLocation(file: "F.swift", line: 1, column: 1)
        )
        return Suggestion(
            templateName: template,
            evidence: [evidence],
            score: Score(signals: [Signal(kind: .typeSymmetrySignature, weight: 30, detail: "")]),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: canonical)
        )
    }

    private func lifted(template: String) -> Suggestion {
        var suggestion = suggestion(template: template, canonical: "lifted")
        suggestion.liftedOrigin = LiftedOrigin(
            testMethodName: "testExample",
            sourceLocation: SourceLocation(file: "FTests.swift", line: 10, column: 1)
        )
        return suggestion
    }
}
