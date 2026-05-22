import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

@Suite("VocabularyLoader — markerPairs / markerSets JSON round-trip (TestLifter M13.0)")
struct VocabularyLoaderMarkerTableTests {

    // MARK: - markerPairs

    @Test("Walk-up loads markerPairs as keyed objects")
    func walkUpLoadsMarkerPairs() throws {
        let root = try makeFixtureDirectory(name: "MarkerPairs")
        defer { try? FileManager.default.removeItem(at: root) }
        try writePackageSwift(at: root)
        try writeVocabulary(at: root, json: """
        {
          "markerPairs": [
            { "positive": "Open", "negative": "Closed" },
            { "positive": "Active", "negative": "Inactive" }
          ]
        }
        """)
        let target = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MyTarget")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let result = VocabularyLoader.load(startingFrom: target)
        #expect(result.warnings.isEmpty)
        #expect(result.vocabulary.markerPairs == [
            MarkerPair(positive: "Open", negative: "Closed"),
            MarkerPair(positive: "Active", negative: "Inactive")
        ])
    }

    @Test("markerPairs decode synonym arrays when present")
    func markerPairsLoadSynonyms() throws {
        let root = try makeFixtureDirectory(name: "MarkerPairsSyn")
        defer { try? FileManager.default.removeItem(at: root) }
        try writePackageSwift(at: root)
        try writeVocabulary(at: root, json: """
        {
          "markerPairs": [
            {
              "positive": "Allowed",
              "negative": "Forbidden",
              "positiveSynonyms": ["Permitted"],
              "negativeSynonyms": ["Denied", "Refused"]
            }
          ]
        }
        """)
        let target = root.appendingPathComponent("Sources/MyTarget")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let result = VocabularyLoader.load(startingFrom: target)
        #expect(result.warnings.isEmpty)
        let pair = try #require(result.vocabulary.markerPairs.first)
        #expect(pair.positiveSynonyms == ["Permitted"])
        #expect(pair.negativeSynonyms == ["Denied", "Refused"])
    }

    @Test("Empty markerPairs array decodes to empty list — fallback inherits curated defaults at consumer")
    func emptyMarkerPairsFallback() throws {
        // The consumer (M13.1 extractor) concatenates
        // MarkerTable.curatedPairs + vocabulary.markerPairs, so an empty
        // project list still gets the curated surface. M13.0's loader
        // contract is just "decode to []" — verifying that here keeps
        // M13.1's concatenation logic load-bearing only at M13.1.
        let root = try makeFixtureDirectory(name: "MarkerPairsEmpty")
        defer { try? FileManager.default.removeItem(at: root) }
        try writePackageSwift(at: root)
        try writeVocabulary(at: root, json: """
        { "markerPairs": [] }
        """)
        let target = root.appendingPathComponent("Sources/MyTarget")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let result = VocabularyLoader.load(startingFrom: target)
        #expect(result.warnings.isEmpty)
        #expect(result.vocabulary.markerPairs.isEmpty)
    }

    // MARK: - markerSets

    @Test("Walk-up loads markerSets as keyed objects")
    func walkUpLoadsMarkerSets() throws {
        let root = try makeFixtureDirectory(name: "MarkerSets")
        defer { try? FileManager.default.removeItem(at: root) }
        try writePackageSwift(at: root)
        try writeVocabulary(at: root, json: """
        {
          "markerSets": [
            { "name": "Sizes", "markers": ["small", "medium", "large"] },
            { "name": "Seasons", "markers": ["spring", "summer", "fall", "winter"] }
          ]
        }
        """)
        let target = root.appendingPathComponent("Sources/MyTarget")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let result = VocabularyLoader.load(startingFrom: target)
        #expect(result.warnings.isEmpty)
        #expect(result.vocabulary.markerSets == [
            MarkerSet(name: "Sizes", markers: ["small", "medium", "large"]),
            MarkerSet(name: "Seasons", markers: ["spring", "summer", "fall", "winter"])
        ])
    }

    @Test("Empty markerSets array decodes to empty list")
    func emptyMarkerSetsFallback() throws {
        let root = try makeFixtureDirectory(name: "MarkerSetsEmpty")
        defer { try? FileManager.default.removeItem(at: root) }
        try writePackageSwift(at: root)
        try writeVocabulary(at: root, json: """
        { "markerSets": [] }
        """)
        let target = root.appendingPathComponent("Sources/MyTarget")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let result = VocabularyLoader.load(startingFrom: target)
        #expect(result.warnings.isEmpty)
        #expect(result.vocabulary.markerSets.isEmpty)
    }

    // MARK: - Pre-M13 back-compat

    @Test("Pre-M13 vocabulary.json without markerPairs / markerSets keys decodes cleanly")
    func preM13SchemaBackCompat() throws {
        // A vocabulary.json on disk that pre-dates M13 (carrying only the
        // M11-era keys) must decode with markerPairs == [] and
        // markerSets == []. Same posture as the existing pre-M7 / pre-M8
        // back-compat probes in VocabularyTests.
        let root = try makeFixtureDirectory(name: "PreM13")
        defer { try? FileManager.default.removeItem(at: root) }
        try writePackageSwift(at: root)
        try writeVocabulary(at: root, json: """
        {
          "inversePairs": [["enqueue", "dequeue"]],
          "idempotenceVerbs": ["normalize"],
          "commutativityVerbs": ["unionGraphs"],
          "antiCommutativityVerbs": ["concatenateOrdered"],
          "monotonicityVerbs": ["depth"],
          "inverseElementVerbs": ["mirror"]
        }
        """)
        let target = root.appendingPathComponent("Sources/MyTarget")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let result = VocabularyLoader.load(startingFrom: target)
        #expect(result.warnings.isEmpty)
        #expect(result.vocabulary.markerPairs.isEmpty)
        #expect(result.vocabulary.markerSets.isEmpty)
        // Other fields still load normally — M13.0 is purely additive.
        #expect(result.vocabulary.idempotenceVerbs == ["normalize"])
        #expect(result.vocabulary.inverseElementVerbs == ["mirror"])
    }

    // MARK: - Combined explicit-path round-trip

    @Test("Explicit path with full marker-table schema round-trips through loader")
    func explicitPathFullMarkerTableRoundTrip() throws {
        let directory = try makeFixtureDirectory(name: "ExplicitFullMarkerTable")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("vocabulary.json")
        let json = """
        {
          "markerPairs": [
            { "positive": "Open", "negative": "Closed" }
          ],
          "markerSets": [
            { "name": "Sizes", "markers": ["small", "medium", "large"] }
          ]
        }
        """
        try Data(json.utf8).write(to: path)
        let result = VocabularyLoader.load(
            startingFrom: directory,
            explicitPath: path
        )
        #expect(result.warnings.isEmpty)
        #expect(result.vocabulary.markerPairs == [
            MarkerPair(positive: "Open", negative: "Closed")
        ])
        #expect(result.vocabulary.markerSets == [
            MarkerSet(name: "Sizes", markers: ["small", "medium", "large"])
        ])
    }

    // MARK: - Helpers (mirror VocabularyLoaderTests)

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("VocabularyLoaderMarkerTableTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writePackageSwift(at root: URL) throws {
        let manifest = root.appendingPathComponent("Package.swift")
        try Data("// swift-tools-version: 6.1\n".utf8).write(to: manifest)
    }

    private func writeVocabulary(at root: URL, json: String) throws {
        let dir = root.appendingPathComponent(".swiftinfer")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("vocabulary.json")
        try Data(json.utf8).write(to: path)
    }
}
