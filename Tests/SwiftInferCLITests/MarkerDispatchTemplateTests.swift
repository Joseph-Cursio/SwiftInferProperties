import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// `marker-dispatch`: a keyword table dispatches every marker to its row's case
/// (SwiftInferProperties#644).
///
/// **The end-to-end evidence is not in this file**, because a unit test cannot compile what it
/// emits: see the PR that introduced the template for the stub compiled and run against
/// `SwiftFormatRuleStudio`, and the mutants it kills there.
@Suite("Marker dispatch — the keyword table restated as an exhaustive check")
struct MarkerDispatchTemplateTests {

    private static let dispatch = MarkerDispatch(
        rows: [
            MarkerRow(literal: "comment", test: .contains, result: ".comments"),
            MarkerRow(literal: "doc", test: .contains, result: ".comments"),
            MarkerRow(literal: "sort", test: .contains, result: ".organization")
        ],
        isCaseInsensitive: true
    )

    private static func summary(
        _ name: String,
        isStatic: Bool = true,
        dispatch: MarkerDispatch? = nil,
        delegation: FallbackDelegation? = nil
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: "for", internalName: "ruleName", typeText: "String", isInout: false)],
            returnTypeText: "FormatRuleCategory",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: isStatic,
            location: SourceLocation(file: "FormatRuleClassifier.swift", line: 16, column: 5),
            containingTypeName: "FormatRuleClassifier",
            bodySignals: BodySignals(
                markerDispatch: dispatch,
                fallbackDelegation: delegation,
                hasNonDeterministicCall: false,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: []
            )
        )
    }

    private static let chain = summary("heuristicCategory", dispatch: dispatch)
    private static let front = summary(
        "category",
        delegation: FallbackDelegation(
            primaryName: "curatedCategory", primaryLabel: "for", fallbackName: "heuristicCategory"
        )
    )

    // MARK: - Proposed

    /// **A private chain reached through a front is entered through the front** — the motivating
    /// subject's `heuristicCategory` is private, and `category(for:)` is how a test reaches it.
    @Test func aChainWithAFrontIsEnteredThroughTheFront() throws {
        let subject = try #require(MarkerDispatchSubject.candidates(in: [Self.front, Self.chain]).first)
        #expect(subject.entry.name == "category")
        #expect(subject.front?.primaryName == "curatedCategory")

        let suggestion = try #require(MarkerDispatchTemplate.suggest(for: subject))
        #expect(suggestion.templateName == "marker-dispatch")
        #expect(suggestion.score.total == 40)
        #expect(suggestion.match?.markerDispatchMatch?.resultType == "FormatRuleCategory")
        #expect(Refutability.isRoleEntailed(suggestion))
        #expect(Refutability.isCharacterisation(suggestion))
    }

    @Test func aChainWithNoFrontIsItsOwnEntry() throws {
        let subject = try #require(MarkerDispatchSubject.candidates(in: [Self.chain]).first)
        #expect(subject.entry.name == "heuristicCategory")
        #expect(subject.front == nil)
    }

    /// The table is a function of its argument; a receiver would make the stub depend on state
    /// the law does not mention.
    @Test func anInstanceMethodChainIsDeclined() {
        let instance = Self.summary("heuristicCategory", isStatic: false, dispatch: Self.dispatch)
        #expect(MarkerDispatchSubject.candidates(in: [instance]).isEmpty)
    }

    // MARK: - Written

    @Test func theStubChecksEveryMarkerThroughTheFrontAndSkipsLookupHits() throws {
        let subject = try #require(MarkerDispatchSubject.candidates(in: [Self.front, Self.chain]).first)
        let suggestion = try #require(MarkerDispatchTemplate.suggest(for: subject))
        let stub = try #require(InteractiveTriage.entailedTemplateStub(for: suggestion, customGenerator: nil))
        #expect(stub.contains("@Test func category_dispatchesEachMarker()"))
        #expect(stub.contains("let table: [(name: String, expected: FormatRuleCategory)] = ["))
        #expect(stub.contains("(\"doc\", .comments),"))
        #expect(stub.contains("(\"sort\", .organization),"))
        #expect(stub.contains("guard FormatRuleClassifier.curatedCategory(for: name) == nil else { continue }"))
        #expect(stub.contains("#expect(FormatRuleClassifier.category(for: name) == expected,"))
        #expect(stub.contains("#expect(checked > 0,"))
    }

    @Test func withoutAFrontNothingIsSkipped() throws {
        let subject = try #require(MarkerDispatchSubject.candidates(in: [Self.chain]).first)
        let suggestion = try #require(MarkerDispatchTemplate.suggest(for: subject))
        let stub = try #require(InteractiveTriage.entailedTemplateStub(for: suggestion, customGenerator: nil))
        #expect(stub.contains("guard ") == false)
        #expect(stub.contains("#expect(FormatRuleClassifier.heuristicCategory(for: name) == expected,"))
    }

    /// A global-actor callee is read synchronously by the loop, so the test carries the actor.
    @Test func aGlobalActorCalleeIsolatesTheTest() {
        let stub = LiftedTestEmitter.markerDispatch(
            callee: CalleeReference(
                bareName: "category", qualifier: "Classifier", argumentLabels: ["for"], isolation: "MainActor"
            ),
            match: MarkerDispatchMatch(dispatch: Self.dispatch, front: nil, resultType: "Category"),
            front: nil
        )
        #expect(stub.contains("@Test @MainActor func category_dispatchesEachMarker()"))
    }
}
