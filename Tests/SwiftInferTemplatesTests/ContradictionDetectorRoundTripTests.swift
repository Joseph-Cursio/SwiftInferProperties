import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("ContradictionDetector — round-trip (PRD §5.6 #3) + mixed corpora")
struct ContradictionDetectorRoundTripTests {

    @Test
    func roundTripKeptWhenBothSidesAreEquatable() throws {
        let (suggestion, pair) = try makeRoundTripSuggestion(domain: "Int", codomain: "String")
        let outcome = ContradictionDetector.filter(
            [suggestion],
            typesToCheck: [suggestion.identity: roundTripTypes(of: pair)],
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
            typesToCheck: [suggestion.identity: roundTripTypes(of: pair)],
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
            typesToCheck: [suggestion.identity: roundTripTypes(of: pair)],
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
            typesToCheck: [suggestion.identity: roundTripTypes(of: pair)],
            resolver: EquatableResolver(typeDecls: [])
        )
        #expect(outcome.kept == [suggestion])
    }

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
                commKeep.identity: commutativityTypes(of: commSummary),
                rtDrop.identity: roundTripTypes(of: rtPair),
                commDrop.identity: commutativityTypes(of: commSummary2),
            ],
            resolver: EquatableResolver(typeDecls: [])
        )
        #expect(outcome.kept == [commKeep])
        #expect(outcome.dropped.count == 2)
        // Drops preserve input order — rtDrop came before commDrop.
        #expect(outcome.dropped[0].suggestion == rtDrop)
        #expect(outcome.dropped[1].suggestion == commDrop)
    }
}
