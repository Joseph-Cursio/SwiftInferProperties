import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The comparator, the predicate and the state machine — the other three shapes application code
/// actually has, and which an algebra-shaped catalogue could not name.
@Suite("Application shapes — comparator, predicate, state machine")
struct ApplicationShapeTemplateTests {

    private static let loc = SourceLocation(file: "FileListing.swift", line: 1, column: 1)

    private func member(
        _ name: String,
        _ parameters: [Parameter],
        returns: String?,
        type: String? = "FileListing",
        isStatic: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: returns,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: isStatic,
            location: Self.loc,
            containingTypeName: type,
            bodySignals: .empty
        )
    }

    private func parameter(_ label: String?, _ type: String) -> Parameter {
        Parameter(label: label, internalName: "value", typeText: type, isInout: false)
    }

    // MARK: - Comparator vs predicate: the same signature, told apart by its labels

    /// Both of these are `(T, T) -> Bool`. Only the **labels** separate them — and in Swift a label
    /// is part of the signature, so this stays a signature test rather than a name test.
    ///
    /// A comparator's operands are interchangeable in position, which is exactly why the ordering
    /// laws are stateable over them. `isImmediateChild(_ path:, of: parent)` gives its second operand
    /// a *role*, so no ordering law applies to it.
    @Test("positional operands make a comparator")
    func positionalOperandsAreAComparator() throws {
        let precedes = member(
            "precedes",
            [parameter(nil, "FileSortKey"), parameter(nil, "FileSortKey")],
            returns: "Bool",
            isStatic: true
        )

        #expect(ComparatorTemplate.isComparator(precedes))
        #expect(PredicateTemplate.isPredicate(precedes) == false)

        let suggestion = try #require(ComparatorTemplate.suggest(for: precedes))
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(suggestion.templateName == "comparator")
        #expect(caveats.contains("STRICT WEAK ORDERING"))
        // The two comparators people actually write, and neither is catchable by example.
        #expect(caveats.contains("REFLEXIVE"))
        #expect(caveats.contains("TRANSITIVITY"))
    }

    @Test("a labelled second operand makes a predicate, not a comparator")
    func labelledOperandIsAPredicate() throws {
        // The road-test's bug site. `(String, String) -> Bool`, identical in shape to `precedes` —
        // but `of:` gives the second operand a role, so there is no ordering to state.
        let isImmediateChild = member(
            "isImmediateChild",
            [parameter(nil, "String"), parameter("of", "String")],
            returns: "Bool",
            isStatic: true
        )

        #expect(ComparatorTemplate.isComparator(isImmediateChild) == false)
        #expect(PredicateTemplate.isPredicate(isImmediateChild))

        let suggestion = try #require(PredicateTemplate.suggest(for: isImmediateChild))
        #expect(suggestion.templateName == "predicate")
    }

    @Test("an operator is neither — the kit already runs its laws")
    func operatorsAreExcluded() {
        // `==` is Equatable's law and `<` is Comparable's; both have executable law suites in the
        // kit. Re-reporting them here would teach the reader that the tools disagree.
        let equals = member("==", [parameter(nil, "Status"), parameter(nil, "Status")], returns: "Bool")

        #expect(ComparatorTemplate.isComparator(equals) == false)
        #expect(PredicateTemplate.isPredicate(equals) == false)
    }

    // MARK: - The predicate carries no free law, and says so

    @Test("the predicate template admits the interesting law is not free")
    func predicateAdmitsItsLimit() throws {
        // The honest boundary of "laws come from role". A comparator owes a strict weak ordering and
        // a partition owes a tiling BY VIRTUE OF BEING ONE. A bare predicate owes only what its
        // domain says it owes — and a tool that invented a law here would be making one up.
        let isValid = member("isValidFolderName", [parameter(nil, "String")], returns: "Bool")
        let suggestion = try #require(PredicateTemplate.suggest(for: isValid))
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n")

        // The one law that IS free.
        #expect(caveats.contains("TOTALITY"))
        // And the honest admission.
        #expect(caveats.contains("THE INTERESTING LAW IS NOT FREE"))
        #expect(caveats.contains("no tool can invent it for you"))
    }

    // MARK: - The state machine, and the false law it must not propose

    @Test("a directional pair with an argument is a state machine")
    func navigationIsAStateMachine() throws {
        let pairs = InverseMutatorPairing.candidates(in: [
            member(
                "navigateToFolder",
                [parameter(nil, "MacCloudFile")],
                returns: nil,
                type: "MacCloudViewModel"
            ),
            member("navigateUp", [], returns: nil, type: "MacCloudViewModel")
        ])

        let pair = try #require(pairs.first)
        #expect(pair.forward.name == "navigateToFolder")
        #expect(pair.backward.name == "navigateUp")

        let suggestion = try #require(StateMachineTemplate.suggest(for: pair))
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(suggestion.templateName == "state-machine")
        // The invariant, not the round trip, is the law worth having.
        #expect(caveats.contains("THE INVARIANT IS THE ONE WORTH HAVING"))
        #expect(caveats.contains("MIND THE PRECONDITION"))
    }

    @Test("selectAll/deselectAll is NOT an inverse pair — the law would be false")
    func absoluteSettersAreNotAnInversePair() {
        // The worst kind of false positive: the tool would propose a law that is WRONG.
        // `deselectAll ∘ selectAll == id` is not true — selectAll sets the selection to everything,
        // deselectAll clears it, and composing them gives the empty set, not the state you started
        // in. A reader who wrote that test would watch it fail for a reason that is not a bug.
        //
        // The gate: the forward move must take an argument — it has to say WHICH way it went, so the
        // backward has something specific to undo. An absolute setter names nothing, because it is
        // not a move at all.
        let pairs = InverseMutatorPairing.candidates(in: [
            member("selectAllFiles", [], returns: nil, type: "MacCloudViewModel"),
            member("deselectAllFiles", [], returns: nil, type: "MacCloudViewModel")
        ])

        #expect(pairs.isEmpty)
    }

    @Test("a value-returning function is not a state-machine move")
    func nonVoidIsNotAMove() {
        let pairs = InverseMutatorPairing.candidates(in: [
            member("open", [parameter(nil, "URL")], returns: "Handle", type: "Store"),
            member("close", [], returns: "Bool", type: "Store")
        ])
        #expect(pairs.isEmpty)
    }
}
