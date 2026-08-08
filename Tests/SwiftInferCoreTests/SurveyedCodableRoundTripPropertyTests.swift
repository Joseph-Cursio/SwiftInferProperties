import Foundation
import PropertyLawKit
@testable import SwiftInferCore
import Testing

// Banked from the `prove-then-show` survey (`docs/measurements/roadtest-self-dogfood-2026-08-08.md`
// §8): five `codable-round-trip` picks the survey **Proved** and that nothing in the repo
// pinned.
//
// **The survey's 81 Proven were not tests.** They were generated into a throwaway verifier
// workdir, compiled, run once, and deleted with it. A Proven verdict is a measurement, not
// regression protection — nothing re-checks it. These five are the subset that is both
// refutable and uncovered: `PersistenceRoundTripPropertyTests` already pins `SeedKind`,
// `Vocabulary`, `SemanticIndexEntry`, `DualStyleNamePair` and `RegisteredGenerator`; these
// were the remainder.
//
// Each of these types hand-writes `encode(to:)` + `init(from:)`, which is exactly the
// population the `codable-round-trip` template targets: a synthesized conformance cannot
// drift from itself, a hand-written pair can.
@Suite("Survey-banked — hand-written Codable round trips the survey proved")
struct SurveyedCodableRoundTripPropertyTests {

    private static func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    // MARK: - InversePair · MarkerPair
    //
    // Two-string records. The law is thin but not vacuous: both hand-roll `init(from:)`, so a
    // field swapped between the two halves survives every example test that happens to use
    // symmetric fixtures. The generator draws asymmetric pairs on purpose.

    private static let wordGen = Gen.element(of: [
        "encode", "decode", "push", "pop", "", "a", "Valid", "Invalid", "read_write"
    ])
    .map { $0! }

    @Test("InversePair round-trips, forward and reverse kept distinct")
    func inversePairRoundTrips() async {
        await propertyCheck(input: Self.wordGen, Self.wordGen) { forward, reverse in
            let pair = InversePair(forward: forward, reverse: reverse)
            let decoded = try? Self.roundTrip(pair)
            #expect(decoded == pair, "InversePair(\(forward), \(reverse)) did not survive")
            #expect(decoded?.forward == forward, "forward and reverse must not be swapped")
        }
    }

    @Test("MarkerPair round-trips, positive and negative kept distinct")
    func markerPairRoundTrips() async {
        await propertyCheck(input: Self.wordGen, Self.wordGen) { positive, negative in
            let pair = MarkerPair(positive: positive, negative: negative)
            let decoded = try? Self.roundTrip(pair)
            #expect(decoded == pair)
            #expect(decoded?.positive == positive, "positive and negative must not be swapped")
        }
    }

    // MARK: - SeedRole · SeedRestriction
    //
    // Both carry an `unrecognised(String)` arm, which is where a round trip earns its keep:
    // an unknown raw must survive rather than collapse to a default.
    //
    // Values are built from the public cases rather than decoded from raw strings, because
    // neither type is `RawRepresentable` — and the raw-decoding contract (a known raw must
    // normalize to its known case, not to `.unrecognised`) is already pinned by
    // `SeedRoleContractTests`. Duplicating it here would restate a guard, not add one.

    private static let roleGen = Gen.element(of: [
        SeedRole.comparator, .predicate, .transform, .reducer, .partition, .normalizer,
        .unrecognised("totally-unknown"), .unrecognised("")
    ])
    .map { $0! }

    private static let restrictionGen = Gen.element(of: [
        SeedRestriction.declaration, .enclosingType,
        .unrecognised("nonsense"), .unrecognised("")
    ])
    .map { $0! }

    @Test("every SeedRole round-trips, known case or unrecognised")
    func seedRoleRoundTrips() async {
        await propertyCheck(input: Self.roleGen) { role in
            #expect(
                (try? Self.roundTrip(role)) == role,
                "SeedRole \(role) did not survive a round trip"
            )
        }
    }

    @Test("every SeedRestriction round-trips, known case or unrecognised")
    func seedRestrictionRoundTrips() async {
        await propertyCheck(input: Self.restrictionGen) { restriction in
            #expect(
                (try? Self.roundTrip(restriction)) == restriction,
                "SeedRestriction \(restriction) did not survive a round trip"
            )
        }
    }

    // MARK: - SeedEffect
    //
    // The richest of the five: two `Tier`s, a `Provenance`, and three optionals that
    // "decode leniently" per its own doc. The optionals are the point — `nil` and absent must
    // be indistinguishable across the trip, which is where a hand-written `init(from:)`
    // usually breaks first.

    private static let tierGen = Gen.element(of: [
        SeedEffect.Tier.pure, .idempotent, .observational, .externallyIdempotent, .nonIdempotent
    ])
    .map { $0! }

    @Test("SeedEffect round-trips across tiers and lenient optionals")
    func seedEffectRoundTrips() async {
        await propertyCheck(
            input: Self.tierGen,
            Self.tierGen,
            Gen.element(of: [nil, 0, 1, 7] as [Int?]).map { $0! }
        ) { declared, resolved, depth in
            let effect = SeedEffect(
                declared: declared,
                resolved: resolved,
                provenance: .declared,
                depth: depth,
                anchor: nil,
                reason: depth == nil ? nil : "inferred over \(depth ?? 0) hops"
            )
            let decoded = try? Self.roundTrip(effect)
            #expect(
                decoded == effect,
                "SeedEffect(\(declared), \(resolved), depth: \(String(describing: depth))) failed"
            )
        }
    }
}
