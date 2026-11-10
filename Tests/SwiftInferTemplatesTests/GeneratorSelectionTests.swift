import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("GeneratorSelection — DerivationStrategy → GeneratorMetadata (M4.2)")
struct GeneratorSelectionTests {

    // MARK: Strategy → (Source, Confidence) calibration table

    @Test
    func userGenStrategyMapsToRegisteredHigh() {
        let (source, confidence) = GeneratorSelection.sourceAndConfidence(for: .userGen)
        #expect(source == .registered)
        #expect(confidence == .high)
    }

    @Test
    func caseIterableStrategyMapsToDerivedCaseIterableHigh() {
        let (source, confidence) = GeneratorSelection.sourceAndConfidence(for: .caseIterable)
        #expect(source == .derivedCaseIterable)
        #expect(confidence == .high)
    }

    @Test
    func rawRepresentableStrategyMapsToDerivedRawRepresentableHigh() {
        let (source, confidence) = GeneratorSelection.sourceAndConfidence(for: .rawRepresentable(.int))
        #expect(source == .derivedRawRepresentable)
        #expect(confidence == .high)
    }

    @Test
    func memberwiseArbitraryStrategyMapsToDerivedMemberwiseMedium() {
        let strategy = DerivationStrategy.memberwiseArbitrary(members: [
            MemberSpec(name: "id", rawType: .int)
        ])
        let (source, confidence) = GeneratorSelection.sourceAndConfidence(for: strategy)
        #expect(source == .derivedMemberwise)
        #expect(confidence == .medium)
    }

    @Test
    func todoStrategyMapsToTodoNilConfidence() {
        let (source, confidence) = GeneratorSelection.sourceAndConfidence(for: .todo(reason: "no strategy"))
        #expect(source == .todo)
        #expect(confidence == nil)
    }

    // MARK: apply — passthrough fast paths

    @Test
    func emptyShapesIndexIsAFastPath() {
        let suggestion = makePlaceholderSuggestion()
        let result = GeneratorSelection.apply(
            to: [suggestion],
            generatorTypeByIdentity: [suggestion.identity: "Widget"],
            shapesByName: [:]
        )
        #expect(result == [suggestion])
    }

    @Test
    func emptyTypeMapIsAFastPath() {
        let suggestion = makePlaceholderSuggestion()
        let shape = TypeShape(
            name: "Widget",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: true
        )
        let result = GeneratorSelection.apply(
            to: [suggestion],
            generatorTypeByIdentity: [:],
            shapesByName: ["Widget": shape]
        )
        #expect(result == [suggestion])
    }

    @Test
    func suggestionWithoutMatchingShapeIsLeftUnchanged() {
        // Open decision #2 default — skip selection for non-corpus types.
        // The suggestion's generator stays .notYetComputed so the
        // renderer can keep showing the M1-placeholder text.
        let suggestion = makePlaceholderSuggestion()
        let result = GeneratorSelection.apply(
            to: [suggestion],
            generatorTypeByIdentity: [suggestion.identity: "MysteryType"],
            shapesByName: [:]
        )
        #expect(result == [suggestion])
        #expect(result.first?.generator.source == .notYetComputed)
    }

    // MARK: apply — populates generator metadata

    @Test
    func apply_populatesDerivedMemberwiseForStdlibMemberStruct() throws {
        // struct Money { let amount: Int; let currency: String } —
        // strategist returns .memberwiseArbitrary; apply rebuilds the
        // suggestion with .derivedMemberwise / .medium.
        let suggestion = makePlaceholderSuggestion(typeText: "Money")
        let shape = TypeShape(
            name: "Money",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: [
                StoredMember(name: "amount", typeName: "Int"),
                StoredMember(name: "currency", typeName: "String"),
            ],
            hasUserInit: false
        )
        let result = GeneratorSelection.apply(
            to: [suggestion],
            generatorTypeByIdentity: [suggestion.identity: "Money"],
            shapesByName: ["Money": shape]
        )
        let lifted = try #require(result.first)
        #expect(lifted.generator.source == .derivedMemberwise)
        #expect(lifted.generator.confidence == .medium)
        // Sampling carries through unchanged — M4.3 will populate it.
        #expect(lifted.generator.sampling == .notRun)
        // All other suggestion fields preserved.
        #expect(lifted.identity == suggestion.identity)
        #expect(lifted.score == suggestion.score)
        #expect(lifted.evidence == suggestion.evidence)
        // WS-1 regression — the generator-carrier must survive the rebuild.
        // makePlaceholderSuggestion is a type-symmetric idempotence pick, so
        // carrierTypeName == typeText; before WS-1 `rebuild` reset it to nil,
        // so the index/verify fell back to the owner type.
        #expect(lifted.carrierTypeName == suggestion.carrierTypeName)
        #expect(lifted.carrierTypeName == "Money")
    }

    // MARK: apply — composite fallback for stdlib / collection carriers (road-test Fix 1)

    /// A non-empty corpus so the `shapesByName.isEmpty` early return doesn't fire,
    /// while the carrier under test is NOT a corpus type.
    private func dummyCorpus() -> [String: TypeShape] {
        [
            "Widget": TypeShape(
            name: "Widget", kind: .struct, inheritedTypes: [],
            hasUserGen: false, storedMembers: [], hasUserInit: false
            ),
        ]
    }

    @Test("apply derives a stdlib collection carrier ([String]) as .derivedComposite")
    func apply_derivesStdlibCollectionCarrier() {
        // A `deindent([String]) -> [String]` / `mergedWith([String]?)`-style carrier:
        // a stdlib composite the corpus doesn't declare. Was skipped to
        // notYetComputed; the composite parser derives it directly.
        let suggestion = makePlaceholderSuggestion(typeText: "[String]")
        let result = GeneratorSelection.apply(
            to: [suggestion],
            generatorTypeByIdentity: [suggestion.identity: "[String]"],
            shapesByName: dummyCorpus()
        )
        #expect(result.first?.generator.source == .derivedComposite)
    }

    @Test("apply derives a bare String carrier as .derivedComposite")
    func apply_derivesStringCarrier() {
        // `isVersion(String, String) -> Bool` — String is trivially generatable.
        let suggestion = makePlaceholderSuggestion(typeText: "String")
        let result = GeneratorSelection.apply(
            to: [suggestion],
            generatorTypeByIdentity: [suggestion.identity: "String"],
            shapesByName: dummyCorpus()
        )
        #expect(result.first?.generator.source == .derivedComposite)
    }

    @Test("apply leaves a non-corpus custom carrier (external Node) at notYetComputed")
    func apply_leavesExternalCustomCarrierNotDerived() {
        // A type the corpus doesn't declare and the composite parser can't
        // recognize (an external Yams `Node`): stays not-derived — the fallback
        // never over-claims. This is the designed `.todo`/gen() boundary.
        let suggestion = makePlaceholderSuggestion(typeText: "Node")
        let result = GeneratorSelection.apply(
            to: [suggestion],
            generatorTypeByIdentity: [suggestion.identity: "Node"],
            shapesByName: dummyCorpus()
        )
        #expect(result.first?.generator.source == .notYetComputed)
    }

    @Test
    func apply_recursivelyDerivesNestedCustomTypeMember() throws {
        // WS-6 Slice 1 — struct Wallet { let balance: Money } where Money is a
        // sibling corpus struct { amount: Int; currency: String }. Without the
        // recursive resolver, Wallet's memberwise derivation can't resolve the
        // custom `Money` member, so the whole strategy falls through to `.todo`.
        // With the resolver threaded in, `Money` resolves (it's itself
        // memberwise-derivable), so Wallet derives as `.derivedMemberwise`.
        let suggestion = makePlaceholderSuggestion(typeText: "Wallet")
        let money = TypeShape(
            name: "Money",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: [
                StoredMember(name: "amount", typeName: "Int"),
                StoredMember(name: "currency", typeName: "String"),
            ],
            hasUserInit: false
        )
        let wallet = TypeShape(
            name: "Wallet",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: [StoredMember(name: "balance", typeName: "Money")],
            hasUserInit: false
        )
        let result = GeneratorSelection.apply(
            to: [suggestion],
            generatorTypeByIdentity: [suggestion.identity: "Wallet"],
            shapesByName: ["Wallet": wallet, "Money": money]
        )
        let lifted = try #require(result.first)
        #expect(lifted.generator.source == .derivedMemberwise)
        #expect(lifted.generator.confidence == .medium)
    }
}
