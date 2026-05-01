import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

// swiftlint:disable type_body_length
// Test suites cohere around their subject — splitting along the 250-line
// body limit would scatter the detector assertions across multiple files
// for no reader benefit.
@Suite("ContradictionDetector — PRD §5.6 #2/#3 cross-cutting filter (M3.4)")
struct ContradictionDetectorTests {

    // MARK: Helpers

    private func makeSummary(
        name: String,
        paramTypes: [String],
        returnType: String?,
        file: String = "Test.swift",
        line: Int = 1
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: paramTypes.enumerated().map { index, type in
                Parameter(label: nil, internalName: "p\(index)", typeText: type, isInout: false)
            },
            returnTypeText: returnType,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: file, line: line, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }

    private func makeCommutativitySuggestion(
        type: String,
        name: String = "merge",
        file: String = "Test.swift",
        line: Int = 1
    ) throws -> (Suggestion, FunctionSummary) {
        let summary = makeSummary(
            name: name,
            paramTypes: [type, type],
            returnType: type,
            file: file,
            line: line
        )
        let suggestion = try #require(CommutativityTemplate.suggest(for: summary))
        return (suggestion, summary)
    }

    private func makeRoundTripSuggestion(
        domain: String,
        codomain: String,
        forwardName: String = "encode",
        reverseName: String = "decode",
        file: String = "Test.swift"
    ) throws -> (Suggestion, FunctionPair) {
        let forward = makeSummary(
            name: forwardName,
            paramTypes: [domain],
            returnType: codomain,
            file: file,
            line: 1
        )
        let reverse = makeSummary(
            name: reverseName,
            paramTypes: [codomain],
            returnType: domain,
            file: file,
            line: 5
        )
        let pair = FunctionPair(forward: forward, reverse: reverse)
        let suggestion = try #require(RoundTripTemplate.suggest(for: pair))
        return (suggestion, pair)
    }

    // MARK: Empty / passthrough

    @Test
    func emptySuggestionsYieldEmptyOutcome() {
        let outcome = ContradictionDetector.filter(
            [],
            typesToCheck: [:],
            resolver: EquatableResolver(typeDecls: [])
        )
        #expect(outcome.kept.isEmpty)
        #expect(outcome.dropped.isEmpty)
    }

    @Test
    func suggestionAbsentFromTypesToCheckPassesThrough() throws {
        let (suggestion, _) = try makeCommutativitySuggestion(type: "Int")
        // Empty typesToCheck — detector treats this as keep (M3.4
        // restricts the contradiction layer to suggestions whose types
        // were registered by the producer).
        let outcome = ContradictionDetector.filter(
            [suggestion],
            typesToCheck: [:],
            resolver: EquatableResolver(typeDecls: [])
        )
        #expect(outcome.kept == [suggestion])
        #expect(outcome.dropped.isEmpty)
    }

    // MARK: Commutativity — PRD §5.6 #2

    @Test
    func commutativityKeptWhenAllTypesAreEquatable() throws {
        let (suggestion, summary) = try makeCommutativitySuggestion(type: "Int")
        let outcome = ContradictionDetector.filter(
            [suggestion],
            typesToCheck: [suggestion.identity: types(commutativity: summary)],
            resolver: EquatableResolver(typeDecls: [])
        )
        #expect(outcome.kept == [suggestion])
        #expect(outcome.dropped.isEmpty)
    }

    @Test
    func commutativityKeptWhenTypesAreUnknown() throws {
        // .unknown stays caveated per M3 plan open decision #1 default —
        // resolver doesn't know `Mystery`, so the suggestion survives.
        let (suggestion, summary) = try makeCommutativitySuggestion(type: "Mystery")
        let outcome = ContradictionDetector.filter(
            [suggestion],
            typesToCheck: [suggestion.identity: types(commutativity: summary)],
            resolver: EquatableResolver(typeDecls: [])
        )
        #expect(outcome.kept == [suggestion])
    }

    @Test
    func commutativityDroppedOnFunctionTypeReturn() throws {
        // A `((Int) -> Int, (Int) -> Int) -> (Int) -> Int` shape — the
        // return type is provably non-Equatable. Drop, with reason text
        // citing the offending type and PRD §5.6 #2.
        let (suggestion, summary) = try makeCommutativitySuggestion(
            type: "(Int) -> Int",
            name: "compose",
            file: "Compose.swift",
            line: 7
        )
        let outcome = ContradictionDetector.filter(
            [suggestion],
            typesToCheck: [suggestion.identity: types(commutativity: summary)],
            resolver: EquatableResolver(typeDecls: [])
        )
        #expect(outcome.kept.isEmpty)
        let drop = try #require(outcome.dropped.first)
        #expect(drop.suggestion == suggestion)
        #expect(drop.reason.contains("commutativity"))
        #expect(drop.reason.contains("compose"))
        #expect(drop.reason.contains("Compose.swift:7"))
        #expect(drop.reason.contains("(Int) -> Int"))
        #expect(drop.reason.contains("not Equatable"))
        #expect(drop.reason.contains("PRD §5.6 #2"))
    }

    @Test
    func commutativityDroppedWhenTypeIsAny() throws {
        let (suggestion, summary) = try makeCommutativitySuggestion(type: "Any", name: "merge")
        let outcome = ContradictionDetector.filter(
            [suggestion],
            typesToCheck: [suggestion.identity: types(commutativity: summary)],
            resolver: EquatableResolver(typeDecls: [])
        )
        #expect(outcome.dropped.count == 1)
    }

    @Test
    func commutativityKeptWhenCorpusDeclaresEquatable() throws {
        // A user type `IntSet: Equatable` — the resolver lifts it to
        // .equatable, so the commutativity suggestion stays.
        let (suggestion, summary) = try makeCommutativitySuggestion(type: "IntSet", name: "merge")
        let typeDecl = TypeDecl(
            name: "IntSet",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            location: SourceLocation(file: "IntSet.swift", line: 1, column: 1)
        )
        let outcome = ContradictionDetector.filter(
            [suggestion],
            typesToCheck: [suggestion.identity: types(commutativity: summary)],
            resolver: EquatableResolver(typeDecls: [typeDecl])
        )
        #expect(outcome.kept == [suggestion])
    }

    // MARK: Round-trip — PRD §5.6 #3

    @Test
    func roundTripKeptWhenBothSidesAreEquatable() throws {
        let (suggestion, pair) = try makeRoundTripSuggestion(domain: "Int", codomain: "String")
        let outcome = ContradictionDetector.filter(
            [suggestion],
            typesToCheck: [suggestion.identity: types(roundTrip: pair)],
            resolver: EquatableResolver(typeDecls: [])
        )
        #expect(outcome.kept == [suggestion])
    }

    @Test
    func roundTripDroppedOnFunctionTypeDomain() throws {
        // domain (Int) -> Int (function type, non-Equatable) ↔ codomain Data.
        // Drop with PRD §5.6 #3 reference.
        let (suggestion, pair) = try makeRoundTripSuggestion(
            domain: "(Int) -> Int",
            codomain: "Data",
            forwardName: "wrap",
            reverseName: "unwrap",
            file: "Wrap.swift"
        )
        let outcome = ContradictionDetector.filter(
            [suggestion],
            typesToCheck: [suggestion.identity: types(roundTrip: pair)],
            resolver: EquatableResolver(typeDecls: [])
        )
        #expect(outcome.kept.isEmpty)
        let drop = try #require(outcome.dropped.first)
        #expect(drop.reason.contains("round-trip"))
        #expect(drop.reason.contains("(Int) -> Int"))
        #expect(drop.reason.contains("PRD §5.6 #3"))
    }

    @Test
    func roundTripDroppedOnAnyObjectCodomain() throws {
        let (suggestion, pair) = try makeRoundTripSuggestion(domain: "Int", codomain: "AnyObject")
        let outcome = ContradictionDetector.filter(
            [suggestion],
            typesToCheck: [suggestion.identity: types(roundTrip: pair)],
            resolver: EquatableResolver(typeDecls: [])
        )
        #expect(outcome.dropped.count == 1)
    }

    @Test
    func roundTripKeptWhenBothSidesAreUnknownCorpusTypes() throws {
        // M3 open decision #1: keep on .unknown.
        let (suggestion, pair) = try makeRoundTripSuggestion(domain: "Foo", codomain: "Bar")
        let outcome = ContradictionDetector.filter(
            [suggestion],
            typesToCheck: [suggestion.identity: types(roundTrip: pair)],
            resolver: EquatableResolver(typeDecls: [])
        )
        #expect(outcome.kept == [suggestion])
    }

    // MARK: Mixed corpora

    @Test
    func mixedSuggestionsPreserveInputOrder() throws {
        let (commKeep, commSummary) = try makeCommutativitySuggestion(
            type: "Int",
            name: "merge",
            file: "A.swift",
            line: 1
        )
        let (rtDrop, rtPair) = try makeRoundTripSuggestion(
            domain: "(Int) -> Int",
            codomain: "Data",
            file: "B.swift"
        )
        let (commDrop, commSummary2) = try makeCommutativitySuggestion(
            type: "Any",
            name: "combine",
            file: "C.swift",
            line: 1
        )
        let outcome = ContradictionDetector.filter(
            [commKeep, rtDrop, commDrop],
            typesToCheck: [
                commKeep.identity: types(commutativity: commSummary),
                rtDrop.identity: types(roundTrip: rtPair),
                commDrop.identity: types(commutativity: commSummary2)
            ],
            resolver: EquatableResolver(typeDecls: [])
        )
        #expect(outcome.kept == [commKeep])
        #expect(outcome.dropped.count == 2)
        // Drops preserve input order — rtDrop came before commDrop.
        #expect(outcome.dropped[0].suggestion == rtDrop)
        #expect(outcome.dropped[1].suggestion == commDrop)
    }

    // MARK: Helpers — mirror TemplateRegistry's per-template type listing

    private func types(commutativity summary: FunctionSummary) -> [String] {
        var out = summary.parameters.map(\.typeText)
        if let returnType = summary.returnTypeText {
            out.append(returnType)
        }
        return out
    }

    private func types(roundTrip pair: FunctionPair) -> [String] {
        var out: [String] = []
        out.append(contentsOf: pair.forward.parameters.map(\.typeText))
        if let returnType = pair.forward.returnTypeText {
            out.append(returnType)
        }
        out.append(contentsOf: pair.reverse.parameters.map(\.typeText))
        if let returnType = pair.reverse.returnTypeText {
            out.append(returnType)
        }
        return out
    }
}
// swiftlint:enable type_body_length
