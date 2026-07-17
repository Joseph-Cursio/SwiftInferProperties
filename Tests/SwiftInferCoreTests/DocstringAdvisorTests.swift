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
