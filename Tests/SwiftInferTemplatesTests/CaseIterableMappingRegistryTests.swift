import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// Registry-level coverage for the `CaseIterable`-mapping family.
///
/// The templates in isolation are pinned by `CaseIterableMappingTemplateTests`;
/// these pin what a unit test on them cannot see — the **wiring**. Both laws are
/// shapes-aware, so they live outside the `singleFunctionAppShapes` registry and
/// its automatic firing test; drop the collector call from
/// `collectApplicationShapeSuggestions` and every isolated test still passes
/// while `discover` silently stops proposing them.
///
/// That is precisely the failure this repo has already had once: `filter-subset`
/// shipped unit-tested but unwired, along with three siblings (see
/// `docs/roadtest-swiftlintrulestudio.md`). These tests are the equivalent guard
/// for this family, and they go through `TypeDecl` rather than `TypeShape`
/// because the real pipeline builds the shapes itself — so they also cover the
/// `TypeShapeBuilder` fold that a hand-made `TypeShape` would bypass.
@Suite("CaseIterable mapping — registry wiring")
struct CaseIterableMappingRegistryTests {

    private static let loc = SourceLocation(file: "Rules.swift", line: 1, column: 1)

    private func member(_ name: String, returns: String, on type: String) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [],
            returnTypeText: returns,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: Self.loc,
            containingTypeName: type,
            bodySignals: .empty,
            isComputedProperty: true
        )
    }

    private func enumDecl(
        _ name: String,
        cases: [String],
        inherits: [String] = ["String", "CaseIterable"]
    ) -> TypeDecl {
        TypeDecl(
            name: name,
            kind: .enum,
            inheritedTypes: inherits,
            location: Self.loc,
            enumCaseNames: cases,
            enumCases: cases.map { EnumCase(name: $0) }
        )
    }

    /// The subject's real shape, shrunk: a `CaseIterable` rule enum and a
    /// category enum carrying `.other`.
    private var decls: [TypeDecl] {
        [
            enumDecl("RuleIdentifier", cases: ["forceTry", "magicNumber", "fatView"]),
            enumDecl("PatternCategory", cases: ["codeQuality", "performance", "other"], inherits: ["CaseIterable"])
        ]
    }

    @Test("discover wires the key-injectivity pass")
    func discoverCollectsKeyInjectivity() {
        let suggestions = TemplateRegistry.discover(
            in: [member("suppressionKey", returns: "String", on: "RuleIdentifier")],
            typeDecls: decls
        )
        #expect(suggestions.contains { $0.templateName == "caseiterable-key-injectivity" })
    }

    @Test("discover wires the case-coverage pass")
    func discoverCollectsCaseCoverage() {
        let suggestions = TemplateRegistry.discover(
            in: [member("category", returns: "PatternCategory", on: "RuleIdentifier")],
            typeDecls: decls
        )
        #expect(suggestions.contains { $0.templateName == "caseiterable-case-coverage" })
    }

    /// The negative that matters through the whole pipeline: a classifier must
    /// not come back proposed as injective.
    @Test("a classifier surfaces coverage and NOT injectivity")
    func classifierDoesNotSurfaceInjectivity() {
        let suggestions = TemplateRegistry.discover(
            in: [member("category", returns: "PatternCategory", on: "RuleIdentifier")],
            typeDecls: decls
        )
        #expect(!suggestions.contains { $0.templateName == "caseiterable-key-injectivity" })
    }

    /// Without the type declarations the enum gate cannot be satisfied, so the
    /// family stays silent rather than guessing. This also proves the gate is
    /// really reading the shapes rather than the member name alone.
    @Test("no type decls means no CaseIterable proposals")
    func shapelessCorpusSurfacesNothing() {
        let suggestions = TemplateRegistry.discover(
            in: [member("suppressionKey", returns: "String", on: "RuleIdentifier")]
        )
        #expect(!suggestions.contains { $0.templateName.hasPrefix("caseiterable-") })
    }

    /// A struct carrier with the same member name and return type earns nothing —
    /// `allCases` is what the law quantifies over.
    @Test("a struct carrier surfaces nothing through the registry")
    func structCarrierSurfacesNothing() {
        let structDecl = TypeDecl(
            name: "Settings", kind: .struct, inheritedTypes: [], location: Self.loc
        )
        let suggestions = TemplateRegistry.discover(
            in: [member("suppressionKey", returns: "String", on: "Settings")],
            typeDecls: [structDecl]
        )
        #expect(!suggestions.contains { $0.templateName.hasPrefix("caseiterable-") })
    }
}
