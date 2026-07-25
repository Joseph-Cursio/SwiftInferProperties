import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The override-precedence law: an explicit value is returned unchanged.
@Suite("Override precedence — an explicit value wins")
struct OverridePrecedenceTemplateTests {

    private static let loc = SourceLocation(file: "Config.swift", line: 120, column: 5)

    private func summary(
        _ name: String,
        params: [Parameter],
        returns: String?,
        on type: String? = "LintConfiguration",
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
            containingTypeName: type,
            bodySignals: .empty
        )
    }

    private func param(_ label: String?, _ internalName: String, _ type: String) -> Parameter {
        Parameter(label: label, internalName: internalName, typeText: type, isInout: false)
    }

    /// The exact shape from the road test.
    private var resolveRules: FunctionSummary {
        summary(
            "resolveRules",
            params: [
                param("cliCategories", "cliCategories", "[PatternCategory]?"),
                param("cliRuleIdentifiers", "cliRuleIdentifiers", "[RuleIdentifier]?")
            ],
            returns: "[RuleIdentifier]?"
        )
    }

    // MARK: - Fires

    @Test("the road-test subject earns the law")
    func resolveRulesFires() throws {
        let suggestion = try #require(OverridePrecedenceTemplate.suggest(for: resolveRules))
        #expect(suggestion.templateName == "override-precedence")

        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: " ")
        #expect(caveats.contains("cliRuleIdentifiers != nil"))
        #expect(caveats.contains("GENERATE THE OTHER ARGUMENTS NON-EMPTY"))
    }

    @Test(
        "each curated override noun is recognised",
        arguments: ["override", "explicitRules", "forcedValue", "requestedSet", "pinnedChoice"]
    )
    func curatedNounsFire(name: String) {
        let function = summary("resolve", params: [param(name, name, "[Rule]?")], returns: "[Rule]?")
        #expect(OverridePrecedenceTemplate.suggest(for: function)?.templateName == "override-precedence")
    }

    // MARK: - Boundary

    /// The type match must be EXACT. A `T` parameter with a `T?` return is an
    /// ordinary wrap, where returning the argument unchanged is not owed.
    @Test("a non-optional parameter against an optional return does not qualify")
    func looseTypeMatchDeclines() {
        let function = summary("resolve", params: [param("override", "override", "[Rule]")], returns: "[Rule]?")
        #expect(OverridePrecedenceTemplate.suggest(for: function) == nil)
    }

    /// A merge function has the same types and a neutral name — and is exactly
    /// the correct code this law would reject, which is why the noun list is
    /// narrow.
    @Test("a neutrally-named parameter of the same type does not qualify")
    func neutralNameDeclines() {
        let function = summary("merged", params: [param("with", "other", "[Rule]?")], returns: "[Rule]?")
        #expect(OverridePrecedenceTemplate.suggest(for: function) == nil)
    }

    @Test("a non-optional return does not qualify")
    func nonOptionalReturnDeclines() {
        let function = summary("resolve", params: [param("override", "override", "[Rule]")], returns: "[Rule]")
        #expect(OverridePrecedenceTemplate.suggest(for: function) == nil)
    }

    @Test("a throwing function is out of scope")
    func throwingDeclines() {
        let function = summary(
            "resolve", params: [param("override", "override", "[Rule]?")],
            returns: "[Rule]?", throws: true
        )
        #expect(OverridePrecedenceTemplate.suggest(for: function) == nil)
    }

    // MARK: - Wiring

    /// The template must be reached through `discover`, not merely be callable.
    @Test("discover wires the override-precedence pass")
    func discoverWiresIt() {
        let suggestions = TemplateRegistry.discover(in: [resolveRules])
        #expect(suggestions.contains { $0.templateName == "override-precedence" })
    }
}
