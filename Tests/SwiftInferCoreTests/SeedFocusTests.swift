import Foundation
@testable import SwiftInferCore
import Testing

@Suite("SeedFocus — manifest decoding + symbol parsing")
struct SeedFocusTests {

    @Test("functionBaseName strips parameter labels")
    func stripsParameterLabels() {
        #expect(SeedFocus.functionBaseName("add(_:_:)") == "add")
        #expect(SeedFocus.functionBaseName("normalize(_:)") == "normalize")
        #expect(SeedFocus.functionBaseName("area(width:height:)") == "area")
    }

    @Test("functionBaseName returns a paren-less name unchanged")
    func parenlessUnchanged() {
        #expect(SeedFocus.functionBaseName("identity") == "identity")
        #expect(SeedFocus.functionBaseName("").isEmpty)
    }

    @Test("SeedManifest decodes the producer's pbt-seeds shape")
    func decodesProducerShape() throws {
        let json = """
        { "version": 1, "seeds": [
            { "file": "Math.swift", "line": 3, "symbol": "add", "rule": "Pure Function Property-Test Candidate" }
        ] }
        """
        let manifest = try JSONDecoder().decode(SeedManifest.self, from: Data(json.utf8))
        #expect(manifest.version == 1)
        #expect(manifest.seeds.count == 1)
        #expect(manifest.seeds.first?.symbol == "add")
        #expect(manifest.seeds.first?.rule == "Pure Function Property-Test Candidate")
    }

    @Test("SeedManifest tolerates a missing rule field")
    func toleratesMissingRule() throws {
        let json = #"{ "version": 1, "seeds": [ { "file": "A.swift", "line": 1, "symbol": "f" } ] }"#
        let manifest = try JSONDecoder().decode(SeedManifest.self, from: Data(json.utf8))
        #expect(manifest.seeds.first?.rule == nil)
        #expect(manifest.seeds.first?.symbol == "f")
    }
}
