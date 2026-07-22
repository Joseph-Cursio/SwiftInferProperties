import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The diff-disjointness template — a diff's added and removed lists never
/// overlap. Fires on a diff-named function whose return type carries a
/// complementary `[T]` pair (`ConfigDiff.addedRules` / `removedRules`).
@Suite("Diff-disjointness — added ∩ removed is empty")
struct DiffDisjointnessTemplateTests {

    private static let loc = SourceLocation(file: "Diff.swift", line: 1, column: 1)

    private func param(_ label: String?, _ type: String) -> Parameter {
        Parameter(label: label, internalName: label ?? "value", typeText: type, isInout: false)
    }

    private func summary(
        _ name: String,
        params: [Parameter],
        returns: String?,
        throws throwing: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: params,
            returnTypeText: returns,
            isThrows: throwing,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: Self.loc,
            containingTypeName: "Engine",
            bodySignals: .empty
        )
    }

    private var configDiffShapes: [String: TypeShape] {
        ["ConfigDiff": TypeShape(
            name: "ConfigDiff",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: [
                StoredMember(name: "addedRules", typeName: "[String]"),
                StoredMember(name: "removedRules", typeName: "[String]"),
                StoredMember(name: "modifiedRules", typeName: "[String]")
            ],
            hasUserInit: false
        )]
    }

    // MARK: - Fires

    @Test("generateDiff -> ConfigDiff owes added/removed disjointness")
    func generateDiffFires() throws {
        let function = summary("generateDiff", params: [param("proposedConfig", "YAMLConfig")], returns: "ConfigDiff")
        let suggestion = try #require(DiffDisjointnessTemplate.suggest(for: function, shapesByName: configDiffShapes))
        #expect(suggestion.templateName == "diff-disjointness")
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(caveats.contains("addedRules"))
        #expect(caveats.contains("removedRules"))
        #expect(caveats.contains("isDisjoint"))
    }

    @Test("a qualified return type (Engine.ConfigDiff) resolves via last component")
    func qualifiedReturnFires() {
        let function = summary(
            "diffConfigs",
            params: [param(nil, "YAMLConfig")],
            returns: "YAMLConfigurationEngine.ConfigDiff"
        )
        #expect(DiffDisjointnessTemplate.suggest(for: function, shapesByName: configDiffShapes) != nil)
    }

    // MARK: - Does not fire

    @Test("a non-diff name does not fire")
    func nonDiffNameRejected() {
        let function = summary("buildReport", params: [param(nil, "YAMLConfig")], returns: "ConfigDiff")
        #expect(DiffDisjointnessTemplate.suggest(for: function, shapesByName: configDiffShapes) == nil)
    }

    @Test("a return type with no complementary pair does not fire")
    func noComplementaryPairRejected() {
        let shapes = ["Plain": TypeShape(
            name: "Plain", kind: .struct, inheritedTypes: [], hasUserGen: false,
            storedMembers: [StoredMember(name: "items", typeName: "[String]")], hasUserInit: false
        )]
        let function = summary("diffThings", params: [param(nil, "X")], returns: "Plain")
        #expect(DiffDisjointnessTemplate.suggest(for: function, shapesByName: shapes) == nil)
    }

    @Test("a throwing diff does not fire (kept off the runnable-law surface)")
    func throwingRejected() {
        let function = summary(
            "diffBetween",
            params: [param(nil, "Backup"), param(nil, "Backup")],
            returns: "ConfigDiff",
            throws: true
        )
        #expect(DiffDisjointnessTemplate.suggest(for: function, shapesByName: configDiffShapes) == nil)
    }
}
