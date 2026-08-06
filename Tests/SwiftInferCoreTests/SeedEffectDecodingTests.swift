import Foundation
@testable import SwiftInferCore
import Testing

/// The wire contract with SwiftProjectLint's `PBTSeedEffect`.
///
/// Two repositories, no shared type, one JSON document — so the only thing
/// holding the schema together is a pair of independently-written decoders and
/// tests like these. The producer's fields are asserted here in the spelling the
/// producer emits, so a rename on either side fails a test rather than silently
/// producing seeds whose effect is always `nil` (which reads exactly like a
/// codebase with no idempotency findings).
@Suite("Seed manifest — decoding the linter's effect tier")
struct SeedEffectDecodingTests {

    private func decode(_ json: String) throws -> SeedManifest {
        let data = try #require(json.data(using: .utf8))
        return try JSONDecoder().decode(SeedManifest.self, from: data)
    }

    /// Verbatim from a real `--format pbt-seeds` run against a three-hop
    /// fixture, so this is a contract test rather than a restatement of the
    /// decoder.
    @Test("a real producer document decodes")
    func realDocumentDecodes() throws {
        let manifest = try decode("""
        {"version":2,"seeds":[{"effect":{"declared":"idempotent","depth":1,
        "provenance":"inferred-upward","resolved":"non_idempotent"},
        "file":"Sources/Demo/Orders.swift","kind":"idempotency","line":11,
        "rule":"Idempotency Violation","symbol":"confirmOrder"}]}
        """)
        let effect = try #require(manifest.seeds.first?.effect)
        #expect(effect.declared == .idempotent)
        #expect(effect.resolved == .nonIdempotent)
        #expect(effect.provenance == .inferredUpward)
        #expect(effect.depth == 1)
    }

    @Test("the heuristic form decodes with its reason")
    func heuristicFormDecodes() throws {
        let manifest = try decode("""
        {"version":2,"seeds":[{"effect":{"declared":"idempotent",
        "provenance":"inferred-downward","reason":"from the callee name `save`",
        "resolved":"non_idempotent"},"file":"A.swift","kind":"idempotency","line":1,
        "rule":"Idempotency Violation","symbol":"f"}]}
        """)
        let effect = try #require(manifest.seeds.first?.effect)
        #expect(effect.provenance == .inferredDownward)
        #expect(effect.reason == "from the callee name `save`")
        #expect(effect.depth == nil)
    }

    /// The grammar spelling is the contract. `nonIdempotent` would decode to
    /// nothing and take the whole seed's effect with it.
    @Test("tiers use the annotation-grammar spelling")
    func grammarSpelling() throws {
        let manifest = try decode("""
        {"version":2,"seeds":[{"effect":{"declared":"observational",
        "provenance":"declared","resolved":"externally_idempotent"},
        "file":"A.swift","kind":"idempotency","line":1,"symbol":"f"}]}
        """)
        let effect = try #require(manifest.seeds.first?.effect)
        #expect(effect.declared == .observational)
        #expect(effect.resolved == .externallyIdempotent)
    }

    /// Every seed written before the field existed, and every seed about purity
    /// rather than retry-safety, has no effect — and must decode.
    @Test("a seed without an effect still decodes")
    func absentEffectDecodes() throws {
        let manifest = try decode("""
        {"version":2,"seeds":[{"file":"Math.swift","line":3,"symbol":"add",
        "kind":"pure-function"}]}
        """)
        #expect(manifest.seeds.first?.effect == nil)
    }

    /// `provenance` decides whether this tool may act at all, so its absence
    /// cannot be defaulted — the same reasoning that made `kind` required after
    /// a silent default nearly produced a confident zero.
    @Test("an effect missing its provenance fails loudly")
    func missingProvenanceThrows() throws {
        let json = """
        {"version":2,"seeds":[{"effect":{"declared":"idempotent","resolved":"non_idempotent"},
        "file":"A.swift","kind":"idempotency","line":1,"symbol":"f"}]}
        """
        let data = try #require(json.data(using: .utf8))
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(SeedManifest.self, from: data)
        }
    }

    /// A tier spelling this build does not know is a producer running ahead of
    /// this consumer. Failing is right — silently reading it as `nil` would let
    /// a new lattice tier arrive as "no finding".
    @Test("an unknown tier fails rather than decoding to nothing")
    func unknownTierThrows() throws {
        let json = """
        {"version":2,"seeds":[{"effect":{"declared":"idempotent","provenance":"declared",
        "resolved":"transactional_idempotent"},"file":"A.swift","kind":"idempotency",
        "line":1,"symbol":"f"}]}
        """
        let data = try #require(json.data(using: .utf8))
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(SeedManifest.self, from: data)
        }
    }
}
