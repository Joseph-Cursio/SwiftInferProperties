import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// `input-order-independence`: a sorted result mapped from a dictionary comes out in the same order
/// for an input and for its reversal (SwiftInferProperties#647, law 2).
///
/// **The end-to-end evidence is not in this file**, because a unit test cannot compile what it
/// emits: see `docs/measurements/input-order-independence.md` for the stub compiled and run against
/// the subjects it was proposed on.
@Suite("Input-order independence — a dictionary's hash order does not reach the result")
struct InputOrderIndependenceTemplateTests {

    /// `SwiftLintRuleStudioTeam`'s `ruleHotspots`: sorted on a count, never on the key.
    private static let hotspotOrdering = SortedOutput(
        member: nil,
        keys: [SortKey(path: "violations", ascending: false)],
        dictionaryKeyMember: "rule"
    )

    private static func summary(
        ordering: SortedOutput? = hotspotOrdering,
        parameterType: String = "[FleetRepo]",
        isThrows: Bool = false,
        isAsync: Bool = false,
        isMutating: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: "ruleHotspots",
            parameters: [Parameter(label: nil, internalName: "repos", typeText: parameterType, isInout: false)],
            returnTypeText: "[RuleHotspot]",
            isThrows: isThrows,
            isAsync: isAsync,
            isMutating: isMutating,
            isStatic: false,
            location: SourceLocation(file: "Derivations.swift", line: 274, column: 1),
            containingTypeName: nil,
            bodySignals: BodySignals(
                sortedOutput: ordering,
                hasNonDeterministicCall: false,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: []
            )
        )
    }

    // MARK: - Proposed

    @Test func aDictionaryFedSortWithAnArrayInputIsProposed() throws {
        let suggestion = try #require(InputOrderIndependenceTemplate.suggest(for: Self.summary()))
        #expect(suggestion.templateName == "input-order-independence")
        #expect(suggestion.match?.sortedOutputMatch == Self.hotspotOrdering)
        #expect(suggestion.score.total == 40)
        #expect(suggestion.explainability.whySuggested.contains {
            $0.contains("never reaches `rule`, so elements tied on (violations ↓) keep the dictionary's hash order")
        })
    }

    /// A comparator that ends on the key holds today; the law then catches the edit that drops it,
    /// and the first caveat says so.
    @Test func aComparatorThatReachesTheKeyIsProposedAsCatchingAnEdit() throws {
        let ordering = SortedOutput(
            member: "ruleImpacts",
            keys: [SortKey(path: "fileCount", ascending: false), SortKey(path: "ruleID", ascending: true)],
            dictionaryKeyMember: "ruleID"
        )
        let suggestion = try #require(
            InputOrderIndependenceTemplate.suggest(for: Self.summary(ordering: ordering))
        )
        #expect(suggestion.explainability.whySuggested.contains { $0.contains("catches an edit that drops it") })
        let firstCaveat = try #require(suggestion.explainability.whyMightBeWrong.first)
        #expect(firstCaveat.hasPrefix("THE COMPARATOR ALREADY REACHES THE KEY"))
    }

    /// Not entailed: a sort key computed from the input's order changes when it is reversed, as meant.
    @Test func itIsAConjectureNotACharacterisation() throws {
        let suggestion = try #require(InputOrderIndependenceTemplate.suggest(for: Self.summary()))
        #expect(Refutability.isRefutable(suggestion))
        #expect(Refutability.isRoleEntailed(suggestion) == false)
        #expect(Refutability.isCharacterisation(suggestion) == false)
    }

    // MARK: - Declined

    @Test func noDictionaryKeyNoSuggestion() {
        let unkeyed = SortedOutput(member: nil, keys: Self.hotspotOrdering.keys)
        #expect(InputOrderIndependenceTemplate.suggest(for: Self.summary(ordering: unkeyed)) == nil)
        #expect(InputOrderIndependenceTemplate.suggest(for: Self.summary(ordering: nil)) == nil)
    }

    @Test("an input that is not an array has no order to permute", arguments: [
        "FleetRepo", "[String: FleetRepo]", "Set<FleetRepo>", "[String: [FleetRepo]]"
    ])
    func noArrayInput(parameterType: String) {
        #expect(InputOrderIndependenceTemplate.suggest(for: Self.summary(parameterType: parameterType)) == nil)
    }

    @Test("array spellings", arguments: [
        "[FleetRepo]", "Array<FleetRepo>", "[(rule: String, count: Int)]", "[[String: Int]]"
    ])
    func arraySpellings(parameterType: String) {
        #expect(InputOrderIndependenceTemplate.isArrayType(parameterType))
    }

    @Test func throwingAsyncAndMutatingSubjectsAreDeclined() {
        #expect(InputOrderIndependenceTemplate.suggest(for: Self.summary(isThrows: true)) == nil)
        #expect(InputOrderIndependenceTemplate.suggest(for: Self.summary(isAsync: true)) == nil)
        #expect(InputOrderIndependenceTemplate.suggest(for: Self.summary(isMutating: true)) == nil)
    }

    // MARK: - Written

    /// The stub calls twice, the second time on the input reversed, and compares the keys in order.
    @Test func theStubComparesTheKeysForTheInputAndItsReversal() throws {
        let suggestion = try #require(InputOrderIndependenceTemplate.suggest(for: Self.summary()))
        let stub = try #require(InteractiveTriage.entailedTemplateStub(for: suggestion, customGenerator: nil))
        #expect(stub.contains("@Test func ruleHotspots_isIndependentOfInputOrder()"))
        #expect(stub.contains(
            "return ruleHotspots(value).map { $0.rule } == ruleHotspots(Array(value.reversed())).map { $0.rule }"
        ))
        #expect(InteractiveTriage.lawClassLine(for: suggestion).contains("Law class: CONJECTURE"))
    }

    /// Only the array is reversed; a drawn receiver and the other arguments are reused as drawn. A
    /// global actor runs the whole comparison inside its hop, as `sortedByKey` does.
    @Test func onlyTheArrayIsReversedAndAGlobalActorHopsOnce() throws {
        let stub = try #require(LiftedTestEmitter.inputOrderIndependent(
            callee: CalleeReference(
                bareName: "from", qualifier: "ImpactReport", argumentLabels: ["findings", "filesChecked"],
                isolation: "MainActor"
            ),
            ordering: SortedOutput(
                member: "ruleImpacts", keys: [SortKey(path: "ruleID", ascending: true)], dictionaryKeyMember: "ruleID"
            ),
            seed: SamplingSeed.derive(fromIdentityHash: "impact"),
            generators: ["[LintFinding].gen()", "Int?.gen()"],
            argumentTypes: ["[LintFinding]", "Int?"],
            failureLabel: "order depends on input order"
        ))
        #expect(stub.contains(
            "await MainActor.run { return "
                + "ImpactReport.from(findings: args.0, filesChecked: args.1).ruleImpacts.map { $0.ruleID } == "
                + "ImpactReport.from(findings: Array(args.0.reversed()), filesChecked: args.1)"
                + ".ruleImpacts.map { $0.ruleID } }"
        ))
    }

    /// An actor receiver awaits each call and compares outside, where the `Sendable` keys are read.
    @Test func anActorReceiverAwaitsEachCall() throws {
        let stub = try #require(LiftedTestEmitter.inputOrderIndependent(
            callee: CalleeReference(
                bareName: "ranked", argumentLabels: [nil], isolation: CalleeReference.actorReceiverIsolation,
                isInstanceMethod: true
            ),
            ordering: Self.hotspotOrdering,
            seed: SamplingSeed.derive(fromIdentityHash: "store"),
            generators: ["Store.gen()", "[FleetRepo].gen()"],
            argumentTypes: ["Store", "[FleetRepo]"],
            failureLabel: "order depends on input order"
        ))
        #expect(stub.contains("let output = await args.0.ranked(args.1).map { $0.rule }; "
            + "let fromReversed = await args.0.ranked(Array(args.1.reversed())).map { $0.rule }; "
            + "return output == fromReversed"))
    }

    /// A law that cannot be written is declined — never written as totality in its place.
    @Test func anUnwritableLawIsDeclinedNotWrittenAsTotality() throws {
        let suggestion = try #require(InputOrderIndependenceTemplate.suggest(for: Self.summary()))
        let unkeyed = Suggestion(
            templateName: suggestion.templateName,
            evidence: suggestion.evidence,
            score: suggestion.score,
            generator: suggestion.generator,
            explainability: suggestion.explainability,
            identity: suggestion.identity,
            match: .sortedOutput(SortedOutput(member: nil, keys: Self.hotspotOrdering.keys))
        )
        #expect(InteractiveTriage.entailedTemplateStub(for: unkeyed, customGenerator: nil) == nil)
    }
}
