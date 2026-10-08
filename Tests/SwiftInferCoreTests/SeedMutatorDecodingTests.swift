import Foundation
import SwiftInferCore
import Testing

/// The producer's `pure-mutator` kind and its two new optional fields, `mutates` and `requires`,
/// decode — and a seed without them is unchanged.
///
/// SwiftProjectLint seeds a pure function that returns nothing and changes one value as a
/// `pure-mutator` naming what it `mutates`, and a function (or mutator) one synthesized `Equatable`
/// away from a law with the types it `requires`. Before this build both fields were dropped on the
/// floor, and the kind decoded as `unrecognised`.
@Suite("Seed manifest — pure-mutator, mutates and requires")
struct SeedMutatorDecodingTests {

    private func decode(_ json: String) throws -> SeedManifest.Seed {
        try JSONDecoder().decode(SeedManifest.Seed.self, from: Data(json.utf8))
    }

    @Test("pure-mutator decodes, is analysable, and round-trips its raw value")
    func pureMutatorKind() throws {
        let seed = try decode("""
        {"file":"M.swift","line":3,"symbol":"add","rule":"Pure Mutator Property-Test Candidate",
         "kind":"pure-mutator","mutates":"config"}
        """)
        #expect(seed.kind == .pureMutator)
        #expect(seed.kind.isAnalysable)
        #expect(seed.kind.rawValue == "pure-mutator")
        #expect(seed.mutates == "config")
    }

    @Test("requires decodes its equatable list, and names the types in its caveat")
    func requiresDecodes() throws {
        let seed = try decode("""
        {"file":"M.swift","line":98,"symbol":"detectMigrations","rule":"Missing Equatable on Pure Function Result",
         "kind":"pure-function","requires":{"equatable":["MigrationPlan","MigrationStep"]}}
        """)
        #expect(seed.requires == SeedRequirement(equatable: ["MigrationPlan", "MigrationStep"]))
        #expect(seed.requires?.caveat.contains("`MigrationPlan` and `MigrationStep`") == true)
    }

    /// The producer keeps every other seed byte-identical; so must the round trip here.
    @Test("a seed without the new fields encodes neither key")
    func absentFieldsAreNotEncoded() throws {
        let seed = SeedManifest.Seed(file: "F.swift", line: 1, symbol: "f", rule: "r")
        let json = try #require(String(bytes: JSONEncoder().encode(seed), encoding: .utf8))
        #expect(json.contains("mutates") == false)
        #expect(json.contains("requires") == false)
    }

    @Test("the new fields survive an encode and decode")
    func newFieldsRoundTrip() throws {
        let seed = SeedManifest.Seed(
            file: "F.swift", line: 1, symbol: "fill", rule: "r", kind: .pureMutator,
            requires: SeedRequirement(equatable: ["Bag"]), mutates: "bag"
        )
        let decoded = try JSONDecoder().decode(SeedManifest.Seed.self, from: JSONEncoder().encode(seed))
        #expect(decoded == seed)
    }

    /// The parity guard opens `requires` as it opens `effect`.
    @Test("requires is a known nested holder")
    func requiresIsAKnownHolder() {
        #expect(SeedFieldParity.knownFields.isSuperset(of: ["mutates", "requires"]))
        #expect(SeedFieldParity.knownNestedFields["requires"] == ["equatable"])
        #expect(SeedFieldParity.unreadFields(under: "requires", emitted: ["equatable", "hashable"]) == ["hashable"])
    }

    @Test("mutator-determinism is a tautology; mutator-idempotence is not")
    func refutability() {
        #expect(Refutability.tautologicalTemplates.contains("mutator-determinism"))
        #expect(Refutability.tautologicalTemplates.contains("mutator-idempotence") == false)
    }
}
