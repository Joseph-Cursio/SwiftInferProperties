import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// Continued in an extension: `type_body_length` counts the primary
/// declaration only, and these are the same suite either way.
extension GeneratorSelectionTests {

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
    func unmappedSuggestionsPassThroughInMixedBatch() {
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
    func makePlaceholderSuggestion(
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
