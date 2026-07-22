import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// Road-test #10 — the registered-generator hook. A project can supply a
/// generator (`Vocabulary.registeredGenerators`) for a type the strategist
/// can't derive (Yams `Node`), so a carrier gated at `.todo` solely by that
/// member composes the rest of itself instead.
@Suite("GeneratorSelection — registered-generator hook (road-test #10)")
struct GeneratorSelectionRegisteredTests {

    @Test("a registered generator unblocks a carrier gated solely by an external member")
    func unblocksCarrierWithExternalMember() {
        // struct YAMLConfig { let rules: [String: Int]; let root: Node } — every
        // member derives except the external Yams `Node`, so memberwise falls
        // through to `.todo`. Registering a generator for `Node` lets the rest
        // of the struct compose: `.derivedMemberwise`.
        let suggestion = makePlaceholderSuggestion(typeText: "YAMLConfig")
        let shape = TypeShape(
            name: "YAMLConfig",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: [
                StoredMember(name: "rules", typeName: "[String: Int]"),
                StoredMember(name: "root", typeName: "Node")
            ],
            hasUserInit: false
        )
        let byIdentity = [suggestion.identity: "YAMLConfig"]
        let shapes = ["YAMLConfig": shape]

        // Without registration: the Node member dead-ends the whole carrier.
        let gated = GeneratorSelection.apply(
            to: [suggestion], generatorTypeByIdentity: byIdentity, shapesByName: shapes
        )
        #expect(gated.first?.generator.source == .todo)

        // With registration: the rest of the struct composes.
        let unblocked = GeneratorSelection.apply(
            to: [suggestion],
            generatorTypeByIdentity: byIdentity,
            shapesByName: shapes,
            registeredGenerators: ["Node": RegisteredGenerator(expression: "Node.gen()", imports: ["Yams"])]
        )
        #expect(unblocked.first?.generator.source == .derivedMemberwise)
        #expect(unblocked.first?.generator.confidence == .medium)
    }

    @Test("a registered generator derives an external carrier directly as .derivedComposite")
    func derivesExternalCarrierDirectly() {
        // The carrier itself is the external `Node` (cf. the boundary test
        // `apply_leavesExternalCustomCarrierNotDerived`, which stays notYetComputed).
        let suggestion = makePlaceholderSuggestion(typeText: "Node")
        let result = GeneratorSelection.apply(
            to: [suggestion],
            generatorTypeByIdentity: [suggestion.identity: "Node"],
            shapesByName: dummyCorpus(),
            registeredGenerators: ["Node": RegisteredGenerator(expression: "Node.gen()")]
        )
        #expect(result.first?.generator.source == .derivedComposite)
    }

    @Test("an empty registration is a no-op — the external boundary is unchanged")
    func emptyRegistrationLeavesExternalCarrierNotDerived() {
        let suggestion = makePlaceholderSuggestion(typeText: "Node")
        let result = GeneratorSelection.apply(
            to: [suggestion],
            generatorTypeByIdentity: [suggestion.identity: "Node"],
            shapesByName: dummyCorpus(),
            registeredGenerators: [:]
        )
        #expect(result.first?.generator.source == .notYetComputed)
    }

    // MARK: - Helpers

    /// A non-empty corpus so the `shapesByName.isEmpty` early return doesn't
    /// fire, while the carrier under test is NOT a corpus type.
    private func dummyCorpus() -> [String: TypeShape] {
        ["Widget": TypeShape(
            name: "Widget", kind: .struct, inheritedTypes: [],
            hasUserGen: false, storedMembers: [], hasUserInit: false
        )]
    }

    private func makePlaceholderSuggestion(typeText: String) -> Suggestion {
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
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        guard let suggestion = IdempotenceTemplate.suggest(for: summary) else {
            fatalError("IdempotenceTemplate must produce a suggestion for the synthetic (\(typeText)) -> \(typeText)")
        }
        return suggestion
    }
}
