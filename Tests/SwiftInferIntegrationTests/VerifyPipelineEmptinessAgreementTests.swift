@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `emptiness-agreement` (#701) built and run against a planted subject, in both directions.
///
/// The unit suite (`EmptinessAgreementVerifySupportTests`) inspects the emitted text. This one
/// compiles it, because the claim that matters is that the member spellings the resolver reads off
/// the index — `value.hasIssues` for a property, `value.totalIssueCount()` for a method — type-check
/// against real members, and that the law refutes the `||` → `&&` mutant it was built for
/// (SwiftLintRuleStudioCore's `CompatibilityReport`, commit 021196a3). The two runs use opposite
/// shapes, so between them both spellings are compiled.
///
/// The calls come from `resolveFunctionCalls` over an index entry, so a resolver that guessed a
/// spelling would fail to build here. Spawns real `swift build`s; tagged `.subprocess` and placed
/// in batch 3 by the `VerifyPipeline` name.
@Suite("Verify pipeline — emptiness-agreement on a planted subject", .tags(.subprocess))
struct VerifyPipelineEmptinessAgreementTests {

    private static let typeShape = IndexedTypeShape(
        name: "Report",
        kind: .struct,
        inheritedTypes: ["Sendable"],
        hasUserGen: false,
        storedMembers: [
            IndexedTypeShape.StoredMember(name: "deprecated", typeName: "Int"),
            IndexedTypeShape.StoredMember(name: "removed", typeName: "Int"),
        ],
        hasUserInit: false
    )

    private static func entry(predicateIsProperty: Bool, measureIsProperty: Bool) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "0xEMPTINESS0001",
            templateName: "emptiness-agreement",
            score: 45,
            tier: "Likely",
            primaryFunctionName: "hasIssues()",
            location: "/Planted.swift:1",
            firstSeenAt: "2026-11-13T00:00:00Z",
            lastSeenAt: "2026-11-13T00:00:00Z",
            typeName: "Report",
            secondaryFunctionName: "totalIssueCount()",
            secondaryMemberShape: MemberAccessShape(isComputedProperty: measureIsProperty),
            carrierTypeName: "Report",
            isInstanceMethod: true,
            isNullary: true,
            isComputedProperty: predicateIsProperty
        )
    }

    private static func run(
        predicate: String,
        measure: String,
        predicateIsProperty: Bool,
        measureIsProperty: Bool
    ) throws -> VerifyOutcome {
        let calls = try SwiftInferCommand.Verify.resolveFunctionCalls(
            for: entry(predicateIsProperty: predicateIsProperty, measureIsProperty: measureIsProperty)
        )
        return try VerifyPipelineIntegrationFixture.runStrategistPipeline(
            functionCalls: calls.expressions,
            carrier: "Report",
            template: "emptiness-agreement",
            typeShape: typeShape,
            preamble: """
                struct Report: Sendable {
                    let deprecated: Int
                    let removed: Int
                \(predicate)
                \(measure)
                }
                """
        )
    }

    /// The count counts the non-empty sections, so it is positive exactly when either is —
    /// at the ordinary draws and at `Int.min` / `Int.max` alike (no arithmetic to overflow).
    @Test("a predicate and a count that agree hold the law in both passes")
    func agreeingMembersPass() throws {
        let outcome = try Self.run(
            predicate: "    var hasIssues: Bool { deprecated > 0 || removed > 0 }",
            measure: "    func totalIssueCount() -> Int { (deprecated > 0 ? 1 : 0) + (removed > 0 ? 1 : 0) }",
            predicateIsProperty: true,
            measureIsProperty: false
        )
        guard case let .bothPass(defaultTrials, edgeTrials, _) = outcome else {
            Issue.record("expected .bothPass; got \(outcome)")
            return
        }
        #expect(defaultTrials > 0)
        #expect(edgeTrials > 0, "the boundary pass must run the law, not the zero-trial sentinel")
    }

    /// The `||` → `&&` mutant: one section non-empty, the predicate says no issues, the count says
    /// one. Refuted by assertion, with both members' values and the law shown.
    @Test("the || → && mutant is refuted, with both members and the law shown")
    func conjunctionMutantFails() throws {
        let outcome = try Self.run(
            predicate: "    func hasIssues() -> Bool { deprecated > 0 && removed > 0 }",
            measure: "    var totalIssueCount: Int { (deprecated > 0 ? 1 : 0) + (removed > 0 ? 1 : 0) }",
            predicateIsProperty: false,
            measureIsProperty: true
        )
        guard case let .defaultFails(detail) = outcome else {
            Issue.record("expected .defaultFails; got \(outcome)")
            return
        }
        #expect(detail.forwardResult == "(false, 1)")
        #expect(detail.inverseResult == "<hasIssues() == (totalIssueCount > 0)>")
        #expect(detail.input.hasPrefix("Report("))
    }
}
