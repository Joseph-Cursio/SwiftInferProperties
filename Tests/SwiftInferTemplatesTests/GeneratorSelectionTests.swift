import ProtoLawCore
import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

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
                StoredMember(name: "currency", typeName: "String")
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
    }

    @Test
    func apply_populatesRegisteredForStaticGenStruct() throws {
        let suggestion = makePlaceholderSuggestion(typeText: "Widget")
        let shape = TypeShape(
            name: "Widget",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: true
        )
        let result = GeneratorSelection.apply(
            to: [suggestion],
            generatorTypeByIdentity: [suggestion.identity: "Widget"],
            shapesByName: ["Widget": shape]
        )
        let lifted = try #require(result.first)
        #expect(lifted.generator.source == .registered)
        #expect(lifted.generator.confidence == .high)
    }

    @Test
    func apply_populatesDerivedCaseIterableForCaseIterableEnum() throws {
        let suggestion = makePlaceholderSuggestion(typeText: "Side")
        let shape = TypeShape(
            name: "Side",
            kind: .enum,
            inheritedTypes: ["CaseIterable"],
            hasUserGen: false
        )
        let result = GeneratorSelection.apply(
            to: [suggestion],
            generatorTypeByIdentity: [suggestion.identity: "Side"],
            shapesByName: ["Side": shape]
        )
        let lifted = try #require(result.first)
        #expect(lifted.generator.source == .derivedCaseIterable)
        #expect(lifted.generator.confidence == .high)
    }

    @Test
    func apply_populatesDerivedRawRepresentableForRawValueEnum() throws {
        let suggestion = makePlaceholderSuggestion(typeText: "StatusCode")
        let shape = TypeShape(
            name: "StatusCode",
            kind: .enum,
            inheritedTypes: ["Int"],
            hasUserGen: false
        )
        let result = GeneratorSelection.apply(
            to: [suggestion],
            generatorTypeByIdentity: [suggestion.identity: "StatusCode"],
            shapesByName: ["StatusCode": shape]
        )
        let lifted = try #require(result.first)
        #expect(lifted.generator.source == .derivedRawRepresentable)
        #expect(lifted.generator.confidence == .high)
    }

    @Test
    func apply_populatesTodoForFallthrough() throws {
        // Class with no .userGen — strategist returns .todo because
        // memberwise derivation only handles structs.
        let suggestion = makePlaceholderSuggestion(typeText: "Logger")
        let shape = TypeShape(
            name: "Logger",
            kind: .class,
            inheritedTypes: [],
            hasUserGen: false
        )
        let result = GeneratorSelection.apply(
            to: [suggestion],
            generatorTypeByIdentity: [suggestion.identity: "Logger"],
            shapesByName: ["Logger": shape]
        )
        let lifted = try #require(result.first)
        #expect(lifted.generator.source == .todo)
        #expect(lifted.generator.confidence == nil)
    }

    // MARK: Mixed — selection only touches mapped suggestions

    @Test
    func unmappedSuggestionsPassThroughInMixedBatch() throws {
        let mapped = makePlaceholderSuggestion(typeText: "Widget", line: 1)
        let unmapped = makePlaceholderSuggestion(typeText: "Other", line: 5)
        let shape = TypeShape(name: "Widget", kind: .struct, inheritedTypes: [], hasUserGen: true)
        let result = GeneratorSelection.apply(
            to: [mapped, unmapped],
            generatorTypeByIdentity: [mapped.identity: "Widget"],
            shapesByName: ["Widget": shape]
        )
        #expect(result.count == 2)
        #expect(result[0].generator.source == .registered)
        #expect(result[1].generator.source == .notYetComputed)
    }

    // MARK: - Helpers

    /// Build a Suggestion the same way `IdempotenceTemplate.suggest` does
    /// for the synthetic `(T) -> T` shape — feeds into apply() tests
    /// that don't depend on the template-side construction.
    private func makePlaceholderSuggestion(
        typeText: String = "Widget",
        line: Int = 1
    ) -> Suggestion {
        let summary = FunctionSummary(
            name: "normalize",
            parameters: [
                Parameter(label: nil, internalName: "v", typeText: typeText, isInout: false)
            ],
            returnTypeText: typeText,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: line, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        // IdempotenceTemplate suggest returns nil unless the score is
        // at least Possible; type symmetry (+30) lands at exactly 30 so
        // we can rely on it for the synthetic input.
        guard let suggestion = IdempotenceTemplate.suggest(for: summary) else {
            fatalError("IdempotenceTemplate must produce a suggestion for the synthetic (\(typeText)) -> \(typeText)")
        }
        return suggestion
    }
}
