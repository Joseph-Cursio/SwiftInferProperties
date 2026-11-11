import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// MARK: - Shared helpers

private func makeContradictionSummary(
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

func makeCommutativitySuggestion(
    type: String,
    name: String = "merge",
    file: String = "Test.swift",
    line: Int = 1
) throws -> (Suggestion, FunctionSummary) {
    let summary = makeContradictionSummary(
        name: name,
        paramTypes: [type, type],
        returnType: type,
        file: file,
        line: line
    )
    let suggestion = try #require(CommutativityTemplate.suggest(for: summary))
    return (suggestion, summary)
}

func makeRoundTripSuggestion(
    domain: String,
    codomain: String,
    forwardName: String = "encode",
    reverseName: String = "decode",
    file: String = "Test.swift"
) throws -> (Suggestion, FunctionPair) {
    let forward = makeContradictionSummary(
        name: forwardName,
        paramTypes: [domain],
        returnType: codomain,
        file: file,
        line: 1
    )
    let reverse = makeContradictionSummary(
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

func commutativityTypes(of summary: FunctionSummary) -> [String] {
    var out = summary.parameters.map(\.typeText)
    if let returnType = summary.returnTypeText {
        out.append(returnType)
    }
    return out
}

func roundTripTypes(of pair: FunctionPair) -> [String] {
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

@Suite("ContradictionDetector — commutativity (PRD §5.6 #2)")
struct ContradictionDetectorCommutativityTests {

    @Test
    func commutativityKeptWhenAllTypesAreEquatable() throws {
        let (suggestion, summary) = try makeCommutativitySuggestion(type: "Int")
        let outcome = ContradictionDetector.filter(
            [suggestion],
            typesToCheck: [suggestion.identity: commutativityTypes(of: summary)],
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
            typesToCheck: [suggestion.identity: commutativityTypes(of: summary)],
            resolver: EquatableResolver(typeDecls: [])
        )
        #expect(outcome.kept == [suggestion])
    }

    @Test
    func commutativityDroppedOnFunctionTypeReturn() throws {
        // A `((Int) -> Int, (Int) -> Int) -> (Int) -> Int` shape — the
        // return type is provably non-Equatable. Drop, with reason text
        // citing the offending type and PRD §5.6 #2. Uses the curated name
        // `merge` so a valid commutativity suggestion is produced for the
        // detector to drop (a bare name would now be gated by B24 upstream).
        let (suggestion, summary) = try makeCommutativitySuggestion(
            type: "(Int) -> Int",
            name: "merge",
            file: "Compose.swift",
            line: 7
        )
        let outcome = ContradictionDetector.filter(
            [suggestion],
            typesToCheck: [suggestion.identity: commutativityTypes(of: summary)],
            resolver: EquatableResolver(typeDecls: [])
        )
        #expect(outcome.kept.isEmpty)
        let drop = try #require(outcome.dropped.first)
        #expect(drop.suggestion == suggestion)
        #expect(drop.reason.contains("commutativity"))
        #expect(drop.reason.contains("merge"))
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
            typesToCheck: [suggestion.identity: commutativityTypes(of: summary)],
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
            typesToCheck: [suggestion.identity: commutativityTypes(of: summary)],
            resolver: EquatableResolver(typeDecls: [typeDecl])
        )
        #expect(outcome.kept == [suggestion])
    }
}
