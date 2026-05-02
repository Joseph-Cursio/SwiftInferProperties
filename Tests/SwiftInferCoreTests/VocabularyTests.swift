import Foundation
import Testing
@testable import SwiftInferCore

@Suite("Vocabulary — PRD §4.5 schema decode/encode")
struct VocabularyTests {

    // MARK: - Decoding

    @Test("Full schema decodes all five keys")
    func fullSchemaDecode() throws {
        let json = """
        {
          "inversePairs": [
            ["enqueue", "dequeue"],
            ["activate", "deactivate"]
          ],
          "idempotenceVerbs": ["sanitizeXML", "rewritePath"],
          "commutativityVerbs": ["unionGraphs"],
          "antiCommutativityVerbs": ["concatenateOrdered"],
          "monotonicityVerbs": ["rank", "tally"]
        }
        """
        let vocab = try decode(json)
        #expect(vocab.inversePairs == [
            InversePair(forward: "enqueue", reverse: "dequeue"),
            InversePair(forward: "activate", reverse: "deactivate")
        ])
        #expect(vocab.idempotenceVerbs == ["sanitizeXML", "rewritePath"])
        #expect(vocab.commutativityVerbs == ["unionGraphs"])
        #expect(vocab.antiCommutativityVerbs == ["concatenateOrdered"])
        #expect(vocab.monotonicityVerbs == ["rank", "tally"])
    }

    @Test("Empty object decodes to .empty")
    func emptyObjectDecode() throws {
        let vocab = try decode("{}")
        #expect(vocab == .empty)
    }

    @Test("Missing keys default to empty arrays — only one key supplied")
    func partialSchemaDecode() throws {
        let json = """
        { "idempotenceVerbs": ["sanitizeXML"] }
        """
        let vocab = try decode(json)
        #expect(vocab.idempotenceVerbs == ["sanitizeXML"])
        #expect(vocab.inversePairs.isEmpty)
        #expect(vocab.commutativityVerbs.isEmpty)
        #expect(vocab.antiCommutativityVerbs.isEmpty)
        #expect(vocab.monotonicityVerbs.isEmpty)
    }

    @Test("Pre-M7 vocabulary files (no monotonicityVerbs key) decode cleanly with empty default")
    func preM7SchemaDecodeBackCompat() throws {
        // Forward-compat probe — a v0.3 vocabulary.json on disk that
        // pre-dates the M7.1 monotonicityVerbs addition must continue
        // to load with monotonicityVerbs == [].
        let json = """
        {
          "inversePairs": [["a", "b"]],
          "idempotenceVerbs": ["c"],
          "commutativityVerbs": ["d"],
          "antiCommutativityVerbs": ["e"]
        }
        """
        let vocab = try decode(json)
        #expect(vocab.monotonicityVerbs.isEmpty)
        #expect(vocab.idempotenceVerbs == ["c"])
    }

    @Test("Unknown top-level keys are silently ignored at the Codable layer")
    func unknownKeysIgnored() throws {
        let json = """
        {
          "idempotenceVerbs": ["sanitizeXML"],
          "futureSignalKeyM3": ["something"],
          "anotherUnknown": 42
        }
        """
        let vocab = try decode(json)
        #expect(vocab.idempotenceVerbs == ["sanitizeXML"])
    }

    @Test("InversePair must be exactly two strings — three rejected")
    func inversePairThreeStringsRejected() {
        let json = """
        { "inversePairs": [["a", "b", "c"]] }
        """
        #expect(throws: DecodingError.self) {
            try decode(json)
        }
    }

    @Test("InversePair must be exactly two strings — one rejected")
    func inversePairOneStringRejected() {
        let json = """
        { "inversePairs": [["only-one"]] }
        """
        #expect(throws: DecodingError.self) {
            try decode(json)
        }
    }

    // MARK: - Encoding

    @Test("Round-trip encode then decode preserves all five lists")
    func roundTripPreservesContents() throws {
        let original = Vocabulary(
            inversePairs: [InversePair(forward: "open", reverse: "close")],
            idempotenceVerbs: ["normalize"],
            commutativityVerbs: ["mergeSets"],
            antiCommutativityVerbs: ["concatenateOrdered"],
            monotonicityVerbs: ["rank", "tally"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Vocabulary.self, from: data)
        #expect(decoded == original)
    }

    @Test("InversePair encodes as a two-element array, not a keyed object")
    func inversePairEncodesAsArray() throws {
        let pair = InversePair(forward: "encode", reverse: "decode")
        let data = try JSONEncoder().encode(pair)
        let json = try #require(String(data: data, encoding: .utf8))
        // JSONEncoder outputs without whitespace by default; the order
        // of two elements in an unkeyed container is deterministic.
        #expect(json == #"["encode","decode"]"#)
    }

    // MARK: - .empty

    @Test(".empty matches a freshly-default-initialised Vocabulary")
    func emptyMatchesDefaultInit() {
        #expect(Vocabulary.empty == Vocabulary())
    }

    // MARK: - Helpers

    private func decode(_ json: String) throws -> Vocabulary {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(Vocabulary.self, from: data)
    }
}
