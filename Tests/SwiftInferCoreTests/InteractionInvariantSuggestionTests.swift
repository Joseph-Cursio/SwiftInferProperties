import Foundation
@testable import SwiftInferCore
import Testing

// V2.0 M4.A — data-model tests for the interaction-invariant
// suggestion shape + the InteractionInvariantFamily enum. Pure:
// no SwiftSyntax.

@Suite("InteractionInvariantSuggestion — V2.0 M4.A data model")
struct InteractionInvariantSuggestionTests {

    private func suggestion(
        family: InteractionInvariantFamily = .conservation,
        reducerQualifiedName: String = "Inbox.body",
        stateTypeName: String = "Inbox.State",
        actionTypeName: String = "Inbox.Action",
        predicate: String = "state.total == state.items.map(\\.price).reduce(0, +)",
        score: Int = 30,
        tier: Tier = .possible,
        whySuggested: [String] = ["stored aggregate + collection witness"],
        whyMightBeWrong: [String] = ["floating-point round-off may cause flakes"]
    ) -> InteractionInvariantSuggestion {
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: family,
            reducerQualifiedName: reducerQualifiedName,
            predicate: predicate
        )
        return InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: family,
            reducerQualifiedName: reducerQualifiedName,
            reducerLocation: "Sources/MyApp/Inbox.swift:42",
            stateTypeName: stateTypeName,
            actionTypeName: actionTypeName,
            predicate: predicate,
            score: score,
            tier: tier,
            whySuggested: whySuggested,
            whyMightBeWrong: whyMightBeWrong,
            firstSeenAt: ISO8601DateFormatter().date(from: "2026-05-15T10:00:00Z")!
        )
    }

    // MARK: - Family enum

    @Test("family rawValues are stable strings — downstream consumers key on them")
    func familyRawValues() {
        #expect(InteractionInvariantFamily.conservation.rawValue == "conservation")
        #expect(InteractionInvariantFamily.idempotence.rawValue == "idempotence")
        #expect(InteractionInvariantFamily.cardinality.rawValue == "cardinality")
        #expect(
            InteractionInvariantFamily.referentialIntegrity.rawValue
                == "referential-integrity"
        )
        #expect(InteractionInvariantFamily.biconditional.rawValue == "biconditional")
        #expect(InteractionInvariantFamily.allCases.count == 5)
    }

    // MARK: - identityCanonicalInput

    @Test("identityCanonicalInput is deterministic for the same (family, reducer, predicate)")
    func identityCanonicalInputDeterminism() {
        let first = InteractionInvariantSuggestion.identityCanonicalInput(
            family: .conservation,
            reducerQualifiedName: "Inbox.body",
            predicate: "state.total >= 0"
        )
        let second = InteractionInvariantSuggestion.identityCanonicalInput(
            family: .conservation,
            reducerQualifiedName: "Inbox.body",
            predicate: "state.total >= 0"
        )
        #expect(first == second)
    }

    @Test("identityCanonicalInput varies on any field — family, reducer, predicate")
    func identityCanonicalInputVariesPerField() {
        let base = InteractionInvariantSuggestion.identityCanonicalInput(
            family: .conservation,
            reducerQualifiedName: "Inbox.body",
            predicate: "state.total >= 0"
        )
        let differentFamily = InteractionInvariantSuggestion.identityCanonicalInput(
            family: .idempotence,
            reducerQualifiedName: "Inbox.body",
            predicate: "state.total >= 0"
        )
        let differentReducer = InteractionInvariantSuggestion.identityCanonicalInput(
            family: .conservation,
            reducerQualifiedName: "Settings.body",
            predicate: "state.total >= 0"
        )
        let differentPredicate = InteractionInvariantSuggestion.identityCanonicalInput(
            family: .conservation,
            reducerQualifiedName: "Inbox.body",
            predicate: "state.total > 0"
        )
        #expect(base != differentFamily)
        #expect(base != differentReducer)
        #expect(base != differentPredicate)
    }

    @Test("derived SuggestionIdentity is byte-stable across calls")
    func derivedIdentityIsStable() {
        let alpha = suggestion()
        let beta = suggestion()
        #expect(alpha.identity == beta.identity)
        #expect(alpha.identity.display.hasPrefix("0x"))
        #expect(alpha.identity.normalized.count == 16)
    }

    // MARK: - Codable round-trip

    @Test("InteractionInvariantSuggestion round-trips through JSONEncoder / JSONDecoder")
    func codableRoundTrip() throws {
        let original = suggestion()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(InteractionInvariantSuggestion.self, from: data)
        #expect(decoded == original)
    }

    @Test("SuggestionIdentity round-trips alongside the v2.0 schema")
    func suggestionIdentityCodableRoundTrip() throws {
        let identity = SuggestionIdentity(canonicalInput: "conservation::Inbox.body::state.total >= 0")
        let data = try JSONEncoder().encode(identity)
        let decoded = try JSONDecoder().decode(SuggestionIdentity.self, from: data)
        #expect(decoded == identity)
    }
}
