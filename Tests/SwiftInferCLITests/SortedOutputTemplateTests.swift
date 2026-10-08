import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// `sorted-output`: a function that returns an array sorted by a tie-break comparator returns it in
/// that comparator's order (SwiftInferProperties#647).
///
/// **The end-to-end evidence is not in this file**, because a unit test cannot compile what it
/// emits: see the PR that introduced the template for the stub compiled and run against
/// `SwiftFormatRuleStudio`, and the mutants it kills there.
@Suite("Sorted output — the comparator restated as a law on the result")
struct SortedOutputTemplateTests {

    private static let impactOrdering = SortedOutput(
        member: "ruleImpacts",
        keys: [
            SortKey(path: "fileCount", ascending: false),
            SortKey(path: "findingCount", ascending: false),
            SortKey(path: "ruleID", ascending: true)
        ]
    )

    private static func summary(
        ordering: SortedOutput? = impactOrdering,
        isThrows: Bool = false,
        isAsync: Bool = false,
        isMutating: Bool = false,
        docComment: String? = nil
    ) -> FunctionSummary {
        FunctionSummary(
            name: "from",
            parameters: [
                Parameter(label: "findings", internalName: "findings", typeText: "[LintFinding]", isInout: false)
            ],
            returnTypeText: "Self",
            isThrows: isThrows,
            isAsync: isAsync,
            isMutating: isMutating,
            isStatic: true,
            location: SourceLocation(file: "ImpactReport.swift", line: 97, column: 5),
            containingTypeName: "ImpactReport",
            bodySignals: BodySignals(
                sortedOutput: ordering,
                hasNonDeterministicCall: false,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: []
            ),
            docComment: docComment
        )
    }

    // MARK: - Proposed

    @Test func aSortedResultIsProposedWithItsOrderingAsTheMatch() throws {
        let suggestion = try #require(SortedOutputTemplate.suggest(for: Self.summary()))
        #expect(suggestion.templateName == "sorted-output")
        #expect(suggestion.match?.sortedOutputMatch == Self.impactOrdering)
        #expect(suggestion.score.total == 40)
        #expect(suggestion.explainability.whySuggested.contains {
            $0.contains("ordered by (fileCount ↓, findingCount ↓, ruleID ↑)")
        })
    }

    /// A doc comment that calls the result sorted or ranked corroborates the law read from the body.
    @Test("a doc comment that calls the result ordered adds corroboration", arguments: [
        "Aggregates raw findings into a ranked per-rule report.",
        "Zero-churn candidates, sorted by name.",
        "Returns the groups in order of size."
    ])
    func orderingDocCorroborates(doc: String) throws {
        let suggestion = try #require(SortedOutputTemplate.suggest(for: Self.summary(docComment: doc)))
        #expect(suggestion.score.total == 60)
    }

    @Test func aDocThatSaysNothingAboutOrderAddsNothing() throws {
        let suggestion = try #require(
            SortedOutputTemplate.suggest(for: Self.summary(docComment: "Aggregates raw findings into a report."))
        )
        #expect(suggestion.score.total == 40)
    }

    /// Read from the body like `guard-domain`, so it is both owed and a characterisation law.
    @Test func itIsRoleEntailedAndACharacterisation() throws {
        let suggestion = try #require(SortedOutputTemplate.suggest(for: Self.summary()))
        #expect(Refutability.isRoleEntailed(suggestion))
        #expect(Refutability.isCharacterisation(suggestion))
    }

    // MARK: - Declined

    @Test func noOrderingNoSuggestion() {
        #expect(SortedOutputTemplate.suggest(for: Self.summary(ordering: nil)) == nil)
    }

    /// The law checks one returned value; a throw, a suspension or a mutation is an outcome it does
    /// not describe.
    @Test func throwingAsyncAndMutatingSubjectsAreDeclined() {
        #expect(SortedOutputTemplate.suggest(for: Self.summary(isThrows: true)) == nil)
        #expect(SortedOutputTemplate.suggest(for: Self.summary(isAsync: true)) == nil)
        #expect(SortedOutputTemplate.suggest(for: Self.summary(isMutating: true)) == nil)
    }

    // MARK: - Written

    /// The stub restates the comparator on each adjacent pair, ending on a NON-STRICT step: two
    /// elements equal on every key are in order, which the comparator's final strict `<` alone
    /// would wrongly call a violation.
    @Test func theStubChecksEveryAdjacentPairInTheComparatorsOrder() throws {
        let suggestion = try #require(SortedOutputTemplate.suggest(for: Self.summary()))
        let stub = try #require(InteractiveTriage.entailedTemplateStub(for: suggestion, customGenerator: nil))
        #expect(stub.contains("@Test func from_isSortedByItsComparator()"))
        #expect(stub.contains("let output = ImpactReport.from(findings: value).ruleImpacts;"))
        #expect(stub.contains("return zip(output, output.dropFirst()).allSatisfy { first, second in "
            + "if first.fileCount != second.fileCount { return first.fileCount > second.fileCount }; "
            + "if first.findingCount != second.findingCount { return first.findingCount > second.findingCount }; "
            + "return first.ruleID <= second.ruleID }"))
    }

    /// ⚠ **Under a global actor the CHECK runs inside the hop, not just the call.** In a module with
    /// `.defaultIsolation(MainActor.self)` the elements' properties are MainActor-isolated, so the
    /// first version — call inside, check outside — failed to compile on SwiftFormatRuleStudio's
    /// `ImpactReport.from` with "main actor-isolated property 'fileCount' can not be referenced".
    @Test func aGlobalActorRunsTheWholeCheckInsideTheHop() {
        let stub = LiftedTestEmitter.sortedByKey(
            callee: CalleeReference(
                bareName: "from", qualifier: "ImpactReport", argumentLabels: ["findings"], isolation: "MainActor"
            ),
            ordering: Self.impactOrdering,
            seed: SamplingSeed.derive(fromIdentityHash: "impact"),
            generators: ["[LintFinding].gen()"],
            failureLabel: "out of order"
        )
        #expect(stub.contains(
            "await MainActor.run { let output = ImpactReport.from(findings: value).ruleImpacts; return zip("
        ))
    }

    /// An actor receiver's hop is a bare `await` per statement, which the check's nested closure
    /// cannot take — so there only the call is isolated, and the `Sendable` result is read outside.
    @Test func anActorReceiverIsolatesOnlyTheCall() {
        let stub = LiftedTestEmitter.sortedByKey(
            callee: CalleeReference(
                bareName: "sessions", argumentLabels: [], isolation: CalleeReference.actorReceiverIsolation,
                isInstanceMethod: true
            ),
            ordering: SortedOutput(member: nil, keys: [SortKey(path: "updatedAt", ascending: false)]),
            seed: SamplingSeed.derive(fromIdentityHash: "store"),
            generators: ["Store.gen()"],
            failureLabel: "out of order"
        )
        #expect(stub.contains("let output = await value.sessions(); return zip(output, output.dropFirst())"))
        #expect(stub.contains("await return") == false)
        #expect(stub.contains("await if") == false)
    }

    /// A descending last key ends on `>=`; a returned array is checked with no member access.
    @Test func aDescendingLastKeyAndADirectlyReturnedArray() {
        let chain = LiftedTestEmitter.inOrderChain([SortKey(path: "count", ascending: false)])
        #expect(chain == "return first.count >= second.count")
        let stub = LiftedTestEmitter.sortedByKey(
            callee: CalleeReference(bareName: "biggestFirst", qualifier: "Groups", argumentLabels: [nil]),
            ordering: SortedOutput(member: nil, keys: [SortKey(path: "count", ascending: false)]),
            seed: SamplingSeed.derive(fromIdentityHash: "groups"),
            generators: ["[Group].gen()"],
            failureLabel: "out of order"
        )
        #expect(stub.contains("let output = Groups.biggestFirst(value);"))
    }
}
