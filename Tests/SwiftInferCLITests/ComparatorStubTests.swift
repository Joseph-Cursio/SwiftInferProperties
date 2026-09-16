import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// `comparator` suggestions are written, and what cannot be written says why (#475).
///
/// Every reachable comparator in the corpus funnel census is `static func precedes…(_ lhs: T, _ rhs:
/// T) -> Bool`, so the arm writes static and free comparators; instance and isolated ones decline
/// with a named reason rather than the generic "no stub writeout available".
@Suite("Comparator — the accept path writes the strict-weak-ordering suite")
struct ComparatorStubTests {

    private static func summary(
        name: String = "precedes",
        operand: String = "LintIssue",
        isStatic: Bool = true,
        owner: String? = "LintIssue",
        globalActor: String? = nil
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(label: nil, internalName: "lhs", typeText: operand, isInout: false),
                Parameter(label: nil, internalName: "rhs", typeText: operand, isInout: false)
            ],
            returnTypeText: "Bool",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: isStatic,
            location: SourceLocation(file: "LintIssue+Ordering.swift", line: 50, column: 5),
            containingTypeName: owner,
            bodySignals: .empty,
            globalActor: globalActor
        )
    }

    private static func suggestion(_ summary: FunctionSummary) throws -> Suggestion {
        try #require(ComparatorTemplate.suggest(for: summary))
    }

    // MARK: - Written

    /// The census's compilable witness: `LintIssue.precedes(_:_:)`, a static comparator.
    @Test func aStaticComparatorIsAQualifiedKitCall() throws {
        let suggestion = try Self.suggestion(Self.summary())
        let resolver: (String) -> String? = { $0 == "LintIssue" ? "Gen<Int>.int().map { LintIssue(line: $0) }" : nil }
        let stub = try #require(InteractiveTriage.entailedTemplateStub(for: suggestion, customGenerator: resolver))
        #expect(stub.contains("by: { LintIssue.precedes($0, $1) }"))
        #expect(stub.contains("over: Gen<Int>.int().map { LintIssue(line: $0) }"))
        #expect(stub.contains("over: Gen<Int>.int(in: 0...4).map { LintIssue(line: $0) }"), "the tie-dense pass")
        #expect(StubApplicationArity.declineReason(for: suggestion) == nil)
    }

    /// A `String` operand's second pass draws from `CollisionBias.alphabet` — the key universe the
    /// template's own `tiedKeys` recipe uses, reached by the rewrite rather than by splicing the recipe.
    @Test func aStringComparatorDrawsFromTheTieAlphabet() throws {
        let suggestion = try Self.suggestion(Self.summary(name: "sortsBefore", operand: "String", owner: "Paths"))
        let stub = try #require(InteractiveTriage.entailedTemplateStub(for: suggestion))
        #expect(stub.components(separatedBy: "try await checkStrictWeakOrderingLaws(").count == 3)
        #expect(stub.contains("[\"a\", \"b\", \"c\"]"))
    }

    /// When rewriting changes nothing — an unresolved `.todo` operand — the suite is not run twice
    /// over one draw.
    @Test func anUnshapeableGeneratorRunsOnce() throws {
        let suggestion = try Self.suggestion(Self.summary(operand: "Opaque", owner: "Opaque"))
        let stub = try #require(InteractiveTriage.entailedTemplateStub(for: suggestion))
        #expect(stub.components(separatedBy: "try await checkStrictWeakOrderingLaws(").count == 2)
    }

    // MARK: - Declined, with a reason

    @Test func anInstanceComparatorDeclinesAndSaysWhy() throws {
        let suggestion = try Self.suggestion(Self.summary(isStatic: false, owner: "Sorter"))
        #expect(InteractiveTriage.entailedTemplateStub(for: suggestion) == nil)
        let reason = try #require(StubApplicationArity.declineReason(for: suggestion))
        #expect(reason.contains("instance method"))
    }

    @Test func anIsolatedComparatorDeclinesAndSaysWhy() throws {
        let suggestion = try Self.suggestion(Self.summary(globalActor: "MainActor"))
        #expect(InteractiveTriage.entailedTemplateStub(for: suggestion) == nil)
        let reason = try #require(StubApplicationArity.declineReason(for: suggestion))
        #expect(reason.contains("MainActor-isolated"))
    }

    // MARK: - The header

    @Test func theFileSaysItIsEntailed() throws {
        let suggestion = try Self.suggestion(Self.summary())
        let stub = try #require(InteractiveTriage.entailedTemplateStub(for: suggestion))
        let file = InteractiveTriage.wrappedFileContents(stub: stub, suggestion: suggestion)
        #expect(file.contains("// Law class: ENTAILED"))
    }
}
