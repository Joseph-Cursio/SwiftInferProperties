import Foundation
import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// `caseiterable-key-injectivity` is written as an exhaustive loop over `allCases` (#474).
///
/// It was one of nine role-entailed templates with no stub writer: accepting it printed *"no stub
/// writeout available"*. The corpus funnel census declined 20, every one over a subject a test
/// could reach, and it needs no generator — the domain is the enum's own case list.
///
/// **Verified by execution, not only by string**: the emitted stub was compiled and run in a scratch
/// package under Swift 6.3 against three enums. A `StaticString` key (not `Hashable`) and a nested
/// `@MainActor` enum both built and passed; an enum with a planted collision failed, reporting
/// `cases sharing a key: ["a ← [Broken.alpha, Broken.gamma]"]`.
@Suite("Case-key injectivity — the accept path writes an exhaustive loop")
struct CaseKeyInjectivityStubTests {

    private static let location = SourceLocation(file: "RuleIdentifier.swift", line: 12, column: 5)

    private static func shapes() -> [String: TypeShape] {
        [
            "RuleIdentifier": TypeShape(
                name: "RuleIdentifier",
                kind: .enum,
                inheritedTypes: ["String", "CaseIterable"],
                hasUserGen: false,
                enumCases: ["forceTry", "magicNumber", "fatView"].map { EnumCase(name: $0) }
            )
        ]
    }

    private static func summary(name: String, computed: Bool, globalActor: String? = nil) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [],
            returnTypeText: "String",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: location,
            containingTypeName: "RuleIdentifier",
            bodySignals: .empty,
            qualifiedContainingTypeName: "Lint.RuleIdentifier",
            isComputedProperty: computed,
            globalActor: globalActor
        )
    }

    /// The suggestion the template really produces — not a hand-built row.
    private static func stub(for summary: FunctionSummary) throws -> String {
        let suggestion = try #require(CaseIterableMappingTemplate.suggest(for: summary, shapesByName: shapes()))
        #expect(suggestion.templateName == "caseiterable-key-injectivity")
        return try #require(InteractiveTriage.entailedTemplateStub(for: suggestion))
    }

    // MARK: - The stub

    @Test func aComputedKeyIsReadAsAPropertyOverEveryCase() throws {
        let stub = try Self.stub(for: Self.summary(name: "suppressionKey", computed: true))
        #expect(stub.contains("@Test func suppressionKey_isInjectiveOverCases() {"))
        #expect(stub.contains(
            "Dictionary(grouping: Lint.RuleIdentifier.allCases, by: { String(describing: $0.suppressionKey) })"
        ))
    }

    @Test func aKeyMethodIsCalled() throws {
        let stub = try Self.stub(for: Self.summary(name: "slug", computed: false))
        #expect(stub.contains("String(describing: $0.slug())"))
    }

    /// **Exhaustive, not sampled** — the template's own instruction. A stub that drew cases would
    /// have to be lucky to find the one colliding pair and would report success when it was not.
    @Test func itLoopsRatherThanSamples() throws {
        let stub = try Self.stub(for: Self.summary(name: "suppressionKey", computed: true))
        #expect(stub.contains("allCases"))
        #expect(stub.contains("backend.check") == false)
        #expect(stub.contains("trials:") == false)
        #expect(stub.contains("Seed(") == false)
    }

    /// The failure names the colliding cases — the actionable half of a red test.
    @Test func aFailureNamesTheCollidingCases() throws {
        let stub = try Self.stub(for: Self.summary(name: "suppressionKey", computed: true))
        #expect(stub.contains("#expect(collisions.isEmpty,"))
        #expect(stub.contains("cases sharing a key:"))
    }

    /// The loop reads the member synchronously, so an isolated member makes the test isolated.
    @Test func anIsolatedMemberMakesTheTestIsolated() throws {
        let stub = try Self.stub(for: Self.summary(name: "suppressionKey", computed: true, globalActor: "MainActor"))
        #expect(stub.contains("@Test @MainActor func suppressionKey_isInjectiveOverCases() {"))
    }

    /// Accepting it no longer reports a missing writer.
    @Test func noDeclineIsReported() throws {
        let summary = Self.summary(name: "suppressionKey", computed: true)
        let suggestion = try #require(CaseIterableMappingTemplate.suggest(for: summary, shapesByName: Self.shapes()))
        #expect(StubApplicationArity.declineReason(for: suggestion) == nil)
        #expect(InteractiveTriage.entailedTemplateStub(for: suggestion) != nil)
    }

    // MARK: - The header

    /// Entailed, and exhaustive — so the ENTAILED line's "a pass is a statement about the code" is
    /// exactly true here, more so than for any sampled law.
    @Test func theFileSaysItIsEntailed() throws {
        let summary = Self.summary(name: "suppressionKey", computed: true)
        let suggestion = try #require(CaseIterableMappingTemplate.suggest(for: summary, shapesByName: Self.shapes()))
        let stub = try #require(InteractiveTriage.entailedTemplateStub(for: suggestion))
        let file = InteractiveTriage.wrappedFileContents(stub: stub, suggestion: suggestion)
        #expect(file.contains("// Law class: ENTAILED"))
    }
}
