import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The selection-subset template — `filter-subset` for a collection nested in a
/// container argument (`layerChain(URL, ConfigTree) -> [DiscoveredConfig]` owes
/// `result ⊆ ConfigTree.configs`). The name gates the shape; the corpus
/// `TypeShape` index supplies the container's `[T]` member.
@Suite("Selection-subset — container-member selection")
struct SelectionSubsetTemplateTests {

    private static let loc = SourceLocation(file: "Sel.swift", line: 1, column: 1)

    private func param(_ label: String?, _ type: String) -> Parameter {
        Parameter(label: label, internalName: label ?? "value", typeText: type, isInout: false)
    }

    private func summary(
        _ name: String,
        params: [Parameter],
        returns: String?,
        mutating: Bool = false,
        async: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: params,
            returnTypeText: returns,
            isThrows: false,
            isAsync: async,
            isMutating: mutating,
            isStatic: false,
            location: Self.loc,
            containingTypeName: "Engine",
            bodySignals: .empty
        )
    }

    /// A `ConfigTree`-like container with a `[DiscoveredConfig]` member.
    private var configTreeShapes: [String: TypeShape] {
        ["ConfigTree": TypeShape(
            name: "ConfigTree",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: [StoredMember(name: "configs", typeName: "[DiscoveredConfig]")],
            hasUserInit: false
        )]
    }

    // MARK: - Fires

    @Test("a layerChain-shaped selection owes the container-member subset law")
    func layerChainShapeFires() throws {
        let function = summary(
            "layerChain",
            params: [param("for", "URL"), param("in", "ConfigTree")],
            returns: "[DiscoveredConfig]"
        )
        let suggestion = try #require(SelectionSubsetTemplate.suggest(for: function, shapesByName: configTreeShapes))
        #expect(suggestion.templateName == "selection-subset")
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(caveats.contains("ConfigTree.configs"))
        #expect(caveats.contains("⊆"))
    }

    // MARK: - Does not fire

    @Test("a non-selection name does not fire")
    func nonSelectionNameRejected() {
        let function = summary("computeConfigs", params: [param("in", "ConfigTree")], returns: "[DiscoveredConfig]")
        #expect(SelectionSubsetTemplate.suggest(for: function, shapesByName: configTreeShapes) == nil)
    }

    @Test("a container with no matching-element member does not fire")
    func noMatchingMemberRejected() {
        // ConfigTree has `[DiscoveredConfig]`, but this returns `[String]`.
        let function = summary("selectNames", params: [param("in", "ConfigTree")], returns: "[String]")
        #expect(SelectionSubsetTemplate.suggest(for: function, shapesByName: configTreeShapes) == nil)
    }

    @Test("a bare [T] argument is left to filter-subset (no double proposal)")
    func directHaystackDeferredToFilterSubset() {
        let function = summary(
            "selectConfigs",
            params: [param(nil, "[DiscoveredConfig]"), param("in", "ConfigTree")],
            returns: "[DiscoveredConfig]"
        )
        #expect(SelectionSubsetTemplate.suggest(for: function, shapesByName: configTreeShapes) == nil)
    }

    @Test("an unknown container type (not in the corpus) does not fire")
    func unknownContainerRejected() {
        let function = summary("layerChain", params: [param("in", "ConfigTree")], returns: "[DiscoveredConfig]")
        #expect(SelectionSubsetTemplate.suggest(for: function, shapesByName: [:]) == nil)
    }

    @Test("a mutating selection does not fire")
    func mutatingRejected() {
        let function = summary(
            "selectInPlace",
            params: [param("in", "ConfigTree")],
            returns: "[DiscoveredConfig]",
            mutating: true
        )
        #expect(SelectionSubsetTemplate.suggest(for: function, shapesByName: configTreeShapes) == nil)
    }
}
