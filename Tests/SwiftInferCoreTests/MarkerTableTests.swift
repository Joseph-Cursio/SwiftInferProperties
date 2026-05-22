import Foundation
@testable import SwiftInferCore
import Testing

@Suite("MarkerTable — TestLifter M13.0 data model")
struct MarkerTableTests {

    // MARK: - MarkerPair

    @Test("MarkerPair — minimal init defaults synonyms to empty arrays")
    func markerPairMinimalInitDefaultsSynonyms() {
        let pair = MarkerPair(positive: "Valid", negative: "Invalid")
        #expect(pair.positive == "Valid")
        #expect(pair.negative == "Invalid")
        #expect(pair.positiveSynonyms.isEmpty)
        #expect(pair.negativeSynonyms.isEmpty)
    }

    @Test("MarkerPair — full init carries synonyms verbatim")
    func markerPairFullInitCarriesSynonyms() {
        let pair = MarkerPair(
            positive: "Allowed",
            negative: "Forbidden",
            positiveSynonyms: ["Permitted", "Authorized"],
            negativeSynonyms: ["Denied"]
        )
        #expect(pair.positiveSynonyms == ["Permitted", "Authorized"])
        #expect(pair.negativeSynonyms == ["Denied"])
    }

    @Test("MarkerPair — Equatable distinguishes synonyms from base form")
    func markerPairEquatableConsidersSynonyms() {
        let bare = MarkerPair(positive: "Valid", negative: "Invalid")
        let withSynonyms = MarkerPair(
            positive: "Valid", negative: "Invalid",
            positiveSynonyms: ["OK"]
        )
        #expect(bare != withSynonyms)
        let bareCopy = MarkerPair(positive: "Valid", negative: "Invalid")
        #expect(bare == bareCopy)
    }

    @Test("MarkerPair — Hashable so it can key dictionaries / sets")
    func markerPairHashable() {
        var bag: Set<MarkerPair> = []
        bag.insert(MarkerPair(positive: "Valid", negative: "Invalid"))
        bag.insert(MarkerPair(positive: "Valid", negative: "Invalid"))
        bag.insert(MarkerPair(positive: "Pass", negative: "Fail"))
        #expect(bag.count == 2)
    }

    @Test("MarkerPair — Codable round-trip preserves bare form")
    func markerPairCodableRoundTripBare() throws {
        let original = MarkerPair(positive: "Valid", negative: "Invalid")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MarkerPair.self, from: data)
        #expect(decoded == original)
    }

    @Test("MarkerPair — Codable round-trip preserves synonyms")
    func markerPairCodableRoundTripWithSynonyms() throws {
        let original = MarkerPair(
            positive: "Pass",
            negative: "Fail",
            positiveSynonyms: ["Succeed"],
            negativeSynonyms: ["Error", "Fault"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MarkerPair.self, from: data)
        #expect(decoded == original)
    }

    @Test("MarkerPair — synonym keys are missing-key-tolerant on decode")
    func markerPairDecodeOmittedSynonyms() throws {
        // Pre-M13 / minimal user-supplied JSON without synonym keys must
        // decode to empty arrays so vocabulary.json files can supply just
        // the (positive, negative) shape and inherit empty synonyms.
        let json = """
        { "positive": "Pass", "negative": "Fail" }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(MarkerPair.self, from: data)
        #expect(decoded.positive == "Pass")
        #expect(decoded.negative == "Fail")
        #expect(decoded.positiveSynonyms.isEmpty)
        #expect(decoded.negativeSynonyms.isEmpty)
    }

    @Test("MarkerPair.defaultTable — M11 narrow surface preserved at M13.0")
    func markerPairDefaultTableUnchanged() {
        // M11.0's extractor + tests still consume MarkerPair.defaultTable;
        // M13.1's refactor switches them to MarkerTable.curatedPairs.
        // Until then, the M11 narrow constant must hold its [Valid/Invalid]
        // single-pair shape verbatim.
        #expect(MarkerPair.defaultTable == [
            MarkerPair(positive: "Valid", negative: "Invalid")
        ])
    }

    // MARK: - MarkerSet

    @Test("MarkerSet — init carries name + markers verbatim")
    func markerSetInit() {
        let set = MarkerSet(name: "Sizes", markers: ["small", "medium", "large"])
        #expect(set.name == "Sizes")
        #expect(set.markers == ["small", "medium", "large"])
    }

    @Test("MarkerSet — Equatable holds")
    func markerSetEquatable() {
        let lhs = MarkerSet(name: "Sizes", markers: ["s", "m", "l"])
        let rhs = MarkerSet(name: "Sizes", markers: ["s", "m", "l"])
        let other = MarkerSet(name: "Sizes", markers: ["s", "m", "xl"])
        #expect(lhs == rhs)
        #expect(lhs != other)
    }

    @Test("MarkerSet — Hashable so it can key dictionaries / sets")
    func markerSetHashable() {
        var bag: Set<MarkerSet> = []
        bag.insert(MarkerSet(name: "Sizes", markers: ["s", "m", "l"]))
        bag.insert(MarkerSet(name: "Sizes", markers: ["s", "m", "l"]))
        bag.insert(MarkerSet(name: "Colors", markers: ["r", "g", "b"]))
        #expect(bag.count == 2)
    }

    @Test("MarkerSet — Codable round-trip")
    func markerSetCodableRoundTrip() throws {
        let original = MarkerSet(name: "Seasons", markers: ["spring", "summer", "fall", "winter"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MarkerSet.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - MarkerTable

    @Test("MarkerTable — default init produces empty pairs + sets")
    func markerTableDefaultInit() {
        let table = MarkerTable()
        #expect(table.pairs.isEmpty)
        #expect(table.sets.isEmpty)
    }

    @Test("MarkerTable — explicit init carries values verbatim")
    func markerTableExplicitInit() {
        let table = MarkerTable(
            pairs: [MarkerPair(positive: "Valid", negative: "Invalid")],
            sets: [MarkerSet(name: "Sizes", markers: ["s", "m", "l"])]
        )
        #expect(table.pairs.count == 1)
        #expect(table.sets.count == 1)
    }

    @Test("MarkerTable — Equatable holds")
    func markerTableEquatable() {
        let lhs = MarkerTable(pairs: MarkerTable.curatedPairs, sets: [])
        let rhs = MarkerTable(pairs: MarkerTable.curatedPairs, sets: [])
        #expect(lhs == rhs)
    }

    @Test("MarkerTable — Codable round-trip preserves curated defaults")
    func markerTableCodableRoundTripCurated() throws {
        let original = MarkerTable(
            pairs: MarkerTable.curatedPairs,
            sets: [MarkerSet(name: "Sizes", markers: ["s", "m", "l"])]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MarkerTable.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Curated defaults sanity (M13 plan OD #1, OD #2)

    @Test("MarkerTable.curatedPairs — five entries per M13 plan OD #1")
    func curatedPairsCount() {
        #expect(MarkerTable.curatedPairs.count == 5)
    }

    @Test("MarkerTable.curatedPairs — exact roster matches OD #1")
    func curatedPairsRoster() {
        let expected: [MarkerPair] = [
            MarkerPair(positive: "Valid", negative: "Invalid"),
            MarkerPair(positive: "Success", negative: "Failure"),
            MarkerPair(positive: "Accept", negative: "Reject"),
            MarkerPair(positive: "Pass", negative: "Fail"),
            MarkerPair(positive: "Allowed", negative: "Forbidden")
        ]
        #expect(MarkerTable.curatedPairs == expected)
    }

    @Test("MarkerTable.curatedPairs — leads with Valid/Invalid for M11 inheritance")
    func curatedPairsLeadsWithValidInvalid() {
        // M11 callers that switch to MarkerTable.curatedPairs at M13.1
        // get the same first-pair classification order they had with
        // MarkerPair.defaultTable, preserving stable suggestion ordering.
        #expect(MarkerTable.curatedPairs.first
            == MarkerPair(positive: "Valid", negative: "Invalid"))
    }

    @Test("MarkerTable.curatedSets — empty per M13 plan OD #2")
    func curatedSetsEmpty() {
        #expect(MarkerTable.curatedSets.isEmpty)
    }
}
