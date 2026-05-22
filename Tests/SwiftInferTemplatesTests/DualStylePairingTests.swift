import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("DualStylePairing — V1.18.C curated naming + shape match")
struct DualStylePairingTests {

    private func summary(
        _ name: String,
        params: [(label: String?, type: String)] = [],
        returnType: String? = nil,
        isMutating: Bool = false,
        containingType: String? = "Bag",
        line: Int = 1
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: params.enumerated().map { index, parameter in
                Parameter(
                    label: parameter.label,
                    internalName: "p\(index)",
                    typeText: parameter.type,
                    isInout: false
                )
            },
            returnTypeText: returnType,
            isThrows: false,
            isAsync: false,
            isMutating: isMutating,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: line, column: 1),
            containingTypeName: containingType,
            bodySignals: .empty
        )
    }

    // MARK: - Curated rules

    @Test("Active / present-participle pair (add / adding) matches")
    func activeToPresentParticiple() {
        let mutator = summary(
            "add",
            params: [(label: nil, type: "Item")],
            returnType: "Void",
            isMutating: true
        )
        let nonMutator = summary(
            "adding",
            params: [(label: nil, type: "Item")],
            returnType: "Bag"
        )
        let pairs = DualStylePairing.candidates(in: [mutator, nonMutator])
        #expect(pairs.count == 1)
        #expect(pairs.first?.rule == .activeToPresentParticiple)
    }

    @Test("Active / past-participle pair (sort / sorted) matches")
    func activeToPastParticiple() {
        let mutator = summary(
            "sort",
            params: [],
            returnType: "Void",
            isMutating: true
        )
        let nonMutator = summary(
            "sorted",
            params: [],
            returnType: "Bag"
        )
        let pairs = DualStylePairing.candidates(in: [mutator, nonMutator])
        #expect(pairs.count == 1)
        #expect(pairs.first?.rule == .activeToPastParticiple)
    }

    @Test("Form-prefix / bare pair (formUnion / union) matches")
    func formPrefixToBare() {
        let mutator = summary(
            "formUnion",
            params: [(label: nil, type: "Bag")],
            returnType: "Void",
            isMutating: true
        )
        let nonMutator = summary(
            "union",
            params: [(label: nil, type: "Bag")],
            returnType: "Bag"
        )
        let pairs = DualStylePairing.candidates(in: [mutator, nonMutator])
        #expect(pairs.count == 1)
        #expect(pairs.first?.rule == .formPrefixToBare)
    }

    @Test("Past-participle drops trailing 'e' (normalize / normalized)")
    func pastParticipleDropsTrailingE() {
        let mutator = summary("normalize", returnType: "Void", isMutating: true)
        let nonMutator = summary("normalized", returnType: "Bag")
        let pairs = DualStylePairing.candidates(in: [mutator, nonMutator])
        #expect(pairs.count == 1)
    }

    @Test("Present-participle drops trailing 'e' before 'ing' (complete / completing)")
    func presentParticipleDropsTrailingE() {
        let mutator = summary("complete", returnType: "Void", isMutating: true)
        let nonMutator = summary("completing", returnType: "Bag")
        let pairs = DualStylePairing.candidates(in: [mutator, nonMutator])
        #expect(pairs.count == 1)
    }

    @Test("Project-vocabulary pair matches when curated rules don't apply")
    func projectVocabularyMatch() {
        let mutator = summary("munge", returnType: "Void", isMutating: true)
        let nonMutator = summary("munged", returnType: "Bag")
        // 'munge' / 'munged' actually fits the past-participle rule already.
        // Use a non-matching shape to force the project-vocab path.
        let exotic1 = summary("rebake", returnType: "Void", isMutating: true)
        let exotic2 = summary("baker", returnType: "Bag")
        let vocab = Vocabulary(dualStyleNamePairs: [
            DualStyleNamePair(mutating: "rebake", nonMutating: "baker")
        ])
        let pairs = DualStylePairing.candidates(
            in: [mutator, nonMutator, exotic1, exotic2],
            vocabulary: vocab
        )
        // Two pairs should surface: one curated, one project-vocab.
        #expect(pairs.count == 2)
        #expect(pairs.contains { $0.rule == .projectVocabulary })
    }

    // MARK: - Filters

    @Test("Mismatched containing types don't pair")
    func mismatchedContainingTypesDontPair() {
        let mutator = summary(
            "add",
            returnType: "Void",
            isMutating: true,
            containingType: "Bag"
        )
        let nonMutator = summary(
            "adding",
            returnType: "Bag",
            containingType: "OtherType"
        )
        #expect(DualStylePairing.candidates(in: [mutator, nonMutator]).isEmpty)
    }

    @Test("Top-level mutating function is impossible — no pair surfaces")
    func topLevelMutatingNoPair() {
        // Top-level functions can't be `mutating` in Swift, but defensively
        // test that the pairing pass filters anything with nil container.
        let mutator = summary(
            "add",
            returnType: "Void",
            isMutating: true,
            containingType: nil
        )
        let nonMutator = summary("adding", returnType: "Bag", containingType: nil)
        #expect(DualStylePairing.candidates(in: [mutator, nonMutator]).isEmpty)
    }

    @Test("Different parameter labels don't pair")
    func differentLabelsDontPair() {
        let mutator = summary(
            "add",
            params: [(label: "item", type: "Item")],
            returnType: "Void",
            isMutating: true
        )
        let nonMutator = summary(
            "adding",
            params: [(label: "other", type: "Item")],
            returnType: "Bag"
        )
        #expect(DualStylePairing.candidates(in: [mutator, nonMutator]).isEmpty)
    }

    @Test("Different parameter types don't pair")
    func differentParameterTypesDontPair() {
        let mutator = summary(
            "add",
            params: [(label: nil, type: "Int")],
            returnType: "Void",
            isMutating: true
        )
        let nonMutator = summary(
            "adding",
            params: [(label: nil, type: "String")],
            returnType: "Bag"
        )
        #expect(DualStylePairing.candidates(in: [mutator, nonMutator]).isEmpty)
    }

    @Test("Non-mutating returning Void doesn't pair (no value-returning sibling)")
    func nonMutatingReturningVoidDoesntPair() {
        let mutator = summary("add", returnType: "Void", isMutating: true)
        let nonMutator = summary("adding", returnType: "Void")
        #expect(DualStylePairing.candidates(in: [mutator, nonMutator]).isEmpty)
    }

    @Test("Non-mutating returning unrelated type doesn't pair")
    func nonMutatingUnrelatedReturnDoesntPair() {
        let mutator = summary("add", returnType: "Void", isMutating: true)
        let nonMutator = summary("adding", returnType: "OtherThing")
        #expect(DualStylePairing.candidates(in: [mutator, nonMutator]).isEmpty)
    }

    @Test("Non-mutating returning Self matches")
    func nonMutatingReturningSelfMatches() {
        let mutator = summary("add", returnType: "Void", isMutating: true)
        let nonMutator = summary("adding", returnType: "Self")
        let pairs = DualStylePairing.candidates(in: [mutator, nonMutator])
        #expect(pairs.count == 1)
    }

    @Test("Non-mutating returning generic specialization of container matches")
    func nonMutatingReturningGenericContainerMatches() {
        // `Bag<Element>` strips to `Bag` and matches the container name.
        let mutator = summary("add", returnType: "Void", isMutating: true)
        let nonMutator = summary("adding", returnType: "Bag<Element>")
        let pairs = DualStylePairing.candidates(in: [mutator, nonMutator])
        #expect(pairs.count == 1)
    }

    @Test("Non-paired names on the same type don't pair")
    func unrelatedNamesDontPair() {
        let mutator = summary(
            "increment",
            params: [(label: "by", type: "Int")],
            returnType: "Void",
            isMutating: true
        )
        let nonMutator = summary(
            "decrement",
            params: [(label: "by", type: "Int")],
            returnType: "Bag"
        )
        #expect(DualStylePairing.candidates(in: [mutator, nonMutator]).isEmpty)
    }

    @Test("Two mutating siblings without a non-mutating partner produce no pair")
    func twoMutatorsNoPair() {
        let mutA = summary("add", returnType: "Void", isMutating: true)
        let mutB = summary("formUnion", returnType: "Void", isMutating: true)
        #expect(DualStylePairing.candidates(in: [mutA, mutB]).isEmpty)
    }

    // MARK: - Determinism

    @Test("Pairs sort by (file, line) for byte-stable output")
    func pairsSortByLocation() {
        let mutA = summary(
            "sort",
            returnType: "Void",
            isMutating: true,
            line: 50
        )
        let nonMutA = summary("sorted", returnType: "Bag", line: 60)
        let mutB = summary(
            "reverse",
            returnType: "Void",
            isMutating: true,
            line: 10
        )
        let nonMutB = summary("reversed", returnType: "Bag", line: 20)
        let pairs = DualStylePairing.candidates(in: [mutA, nonMutA, mutB, nonMutB])
        #expect(pairs.count == 2)
        #expect(pairs[0].mutatingMember.name == "reverse")
        #expect(pairs[1].mutatingMember.name == "sort")
    }

    // MARK: - Naming-rule helpers

    @Test("matchRule returns nil when none of the curated rules apply")
    func matchRuleReturnsNilWhenNoCuratedMatch() {
        #expect(DualStylePairing.matchRule(
            mutating: "increment",
            nonMutating: "decrement",
            vocabulary: .empty
        ) == nil)
    }
}
