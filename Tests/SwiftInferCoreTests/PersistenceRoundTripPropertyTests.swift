import Foundation
import PropertyLawKit
import SwiftInferCore
import Testing

// Self-dogfood road test (`docs/roadtest-self-dogfood.md`) — the largest group
// `swift-infer discover --target SwiftInferCore` surfaced: seven
// `codable-round-trip` candidates at default tier, every one of them a type with
// a **hand-written** `encode(to:)` / `init(from:)` pair.
//
// That is exactly where the law earns its keep. Swift's synthesized `Codable`
// cannot forget a field; a hand-written pair can, and does so silently — the
// field simply reads back as its default on the next load, with no error at
// either end. `SemanticIndexEntry` hand-encodes nineteen fields across two
// methods that must be kept in lockstep by hand, and it is the row type of
// `.swiftinfer/index.json`, which every downstream surface (`query`, `report`,
// `insights`, `docc`) reads.
//
// The generators below therefore fill **every** field with a distinguishable
// value rather than leaning on defaults. A round-trip test whose inputs are
// mostly defaults passes whether or not the encoder writes them — it is the
// green-for-the-wrong-reason shape, and it is easy to write by accident.
@Suite("Road test — hand-written Codable round trips")
struct PersistenceRoundTripPropertyTests {

    private static let coder = (encoder: JSONEncoder(), decoder: JSONDecoder())

    private static func roundTrip<T: Codable>(_ value: T) throws -> T {
        try coder.decoder.decode(T.self, from: coder.encoder.encode(value))
    }

    // MARK: - SeedKind — the cross-repo contract with SwiftProjectLint

    /// Every seed kind SwiftProjectLint can emit round-trips, **including kinds
    /// this build has never heard of**.
    ///
    /// This is the law that protects the producer/consumer seam: the linter
    /// writes `{file, line, symbol, kind}` and `swift-infer` reads it, so a
    /// newer linter emitting a kind this binary does not know must survive a
    /// decode/encode cycle unchanged rather than being silently rewritten. The
    /// `.unrecognised` case exists precisely for that, and its docstring is
    /// emphatic — "never silently narrow to a symbol you do not understand."
    @Test("every seed kind round-trips, known or not")
    func seedKindRoundTrips() async throws {
        let known = ["pure-function", "idempotency", "extractable-kernel"]
        for raw in known {
            let decoded = try Self.roundTrip(SeedKind.unrecognised(raw))
            #expect(decoded.rawValue == raw)
        }
        // Unknown kinds — the forward-compatibility case.
        await propertyCheck(input: Gen.lowercaseLetter.string(of: 1...12)) { raw in
            guard !known.contains(raw), !raw.isEmpty else { return }
            let kind = SeedKind.unrecognised(raw)
            let decoded = try? Self.roundTrip(kind)
            #expect(decoded == kind, "an unknown kind was rewritten on round trip")
            #expect(decoded?.isAnalysable == false, "an unknown kind must not be treated as analysable")
        }
    }

    /// **A hand-constructed `.unrecognised` of a *known* raw value does not
    /// round-trip — it normalizes.** `rawValue` returns the raw string, so
    /// `.unrecognised("pure-function")` encodes as `"pure-function"` and decodes
    /// as `.pureFunction`.
    ///
    /// This is not a defect: the decoder never *produces* such a value, so the
    /// round-trip law holds over the decoder's image, which is the domain that
    /// matters for the wire format. It is recorded because the naive statement
    /// of the law — "round-trip holds for all `SeedKind`" — is false, and
    /// because the type carries the same unenforced invariant shape found in
    /// `Decisions` (see `MergeAlgebraPropertyTests`): a case whose payload is
    /// constrained by convention and by nothing else.
    @Test("an .unrecognised of a known raw normalizes rather than round-tripping")
    func unrecognisedOfKnownRawNormalizes() throws {
        let masquerading = SeedKind.unrecognised("pure-function")
        #expect(masquerading != .pureFunction)
        #expect(masquerading.isAnalysable == false)

        let decoded = try Self.roundTrip(masquerading)
        #expect(decoded == .pureFunction, "normalized, not preserved")
        #expect(decoded.isAnalysable == true, "…and its analysability flipped in the process")
    }

    // MARK: - SeedManifest

    /// Includes `.unrecognised` — a manifest written by a newer linter than
    /// this build is exactly the case the wire format has to survive.
    private static let seedKinds: [SeedKind] = [
        .pureFunction, .idempotency, .extractableKernel, .unrecognised("future-kind")
    ]

    private static let seedGen = zip(
        Gen.lowercaseLetter.string(of: 1...10),
        Gen<Int>.int(in: 1...9_999),
        Gen.lowercaseLetter.string(of: 1...10),
        Gen.element(of: seedKinds)
    ).map { file, line, symbol, kind in
        SeedManifest.Seed(
            file: file + ".swift",
            line: line,
            symbol: symbol,
            rule: "Pure Function Property-Test Candidate",
            kind: kind!
        )
    }

    @Test("SeedManifest round-trips with every field populated")
    func seedManifestRoundTrips() async {
        await propertyCheck(input: Self.seedGen.array(of: 0...5)) { seeds in
            let manifest = SeedManifest(seeds: seeds)
            let decoded = try? Self.roundTrip(manifest)
            #expect(decoded == manifest)
            #expect(decoded?.seeds.count == seeds.count)
        }
    }

    // MARK: - SemanticIndexEntry — nineteen hand-encoded fields

    /// Every field distinct and non-default, so a forgotten `encode` line
    /// cannot hide behind a default value on the way back in.
    private static let indexEntryGen = zip(
        Gen<Int>.int(in: 0...120),
        Gen.element(of: Tier.allCases).map { $0!.label },
        Gen.element(of: [true, false]).map { $0! },
        Gen.element(of: [true, false]).map { $0! }
    ).map { score, tier, flagA, flagB in
        SemanticIndexEntry(
            identityHash: "ABCDEF0123456789",
            templateName: "idempotence",
            typeName: "Carrier",
            score: score,
            tier: tier,
            primaryFunctionName: "normalize",
            location: "Carrier.swift:12",
            decision: "accepted",
            decisionAt: "2026-07-26T00:00:00Z",
            firstSeenAt: "2026-07-01T00:00:00Z",
            lastSeenAt: "2026-07-26T00:00:00Z",
            typeShape: nil,
            secondaryFunctionName: "denormalize",
            carrierTypeName: "Carrier",
            isInstanceMethod: flagA,
            isMutatingMethod: flagB,
            isNullary: flagA,
            returnsSelfType: flagB,
            isComputedProperty: flagA
        )
    }

    /// The round-trip law `discover` proposed, stated so that it is actually
    /// refutable: every optional is `.some`, every `Bool` is generated rather
    /// than defaulted, and the assertion is on the whole value.
    ///
    /// The five trailing `Bool` columns are the ones at risk. They were added
    /// after the type shipped, they all default to `false` in both the
    /// initializer and the decoder, and they are encoded by five separate
    /// hand-written lines — so omitting any one of them produces a round trip
    /// that is wrong only when the flag is `true`.
    @Test("SemanticIndexEntry round-trips every field, including the Bool columns")
    func indexEntryRoundTripsEveryField() async {
        await propertyCheck(input: Self.indexEntryGen) { entry in
            let decoded = try? Self.roundTrip(entry)
            #expect(decoded == entry)
        }
    }

    /// The same law aimed squarely at the risk above: force every `Bool` column
    /// to `true`, so a dropped `encode` line cannot round-trip by coincidence.
    @Test("SemanticIndexEntry preserves Bool columns set to true")
    func indexEntryPreservesTrueFlags() throws {
        let entry = SemanticIndexEntry(
            identityHash: "ABCDEF0123456789",
            templateName: "idempotence",
            typeName: "Carrier",
            score: 80,
            tier: "Strong",
            primaryFunctionName: "normalize",
            location: "Carrier.swift:12",
            firstSeenAt: "2026-07-01T00:00:00Z",
            lastSeenAt: "2026-07-26T00:00:00Z",
            isInstanceMethod: true,
            isMutatingMethod: true,
            isNullary: true,
            returnsSelfType: true,
            isComputedProperty: true
        )
        let decoded = try Self.roundTrip(entry)
        #expect(decoded.isInstanceMethod)
        #expect(decoded.isMutatingMethod)
        #expect(decoded.isNullary)
        #expect(decoded.returnsSelfType)
        #expect(decoded.isComputedProperty)
        #expect(decoded == entry)
    }

    // MARK: - Vocabulary — the user-supplied config

    /// `Vocabulary` is read from a user's `.swiftinfer/vocabulary.json`, so a
    /// dropped field is a user's curated verb list vanishing without a
    /// diagnostic. Eleven hand-encoded collections, all populated here.
    @Test("Vocabulary round-trips with every list populated")
    func vocabularyRoundTrips() throws {
        let vocabulary = Vocabulary(
            inversePairs: [],
            idempotenceVerbs: ["normalize"],
            commutativityVerbs: ["union"],
            antiCommutativityVerbs: ["subtract"],
            monotonicityVerbs: ["depth"],
            inverseElementVerbs: ["negate"],
            markerPairs: [],
            markerSets: [],
            dualStyleNamePairs: [DualStyleNamePair(mutating: "sort", nonMutating: "sorted")],
            compositionVerbs: ["advance"],
            registeredGenerators: [
                "YAMLConfig": RegisteredGenerator(expression: "YAMLConfig.gen()", imports: ["Yams"])
            ]
        )
        let decoded = try Self.roundTrip(vocabulary)
        #expect(decoded == vocabulary)
        // Named individually: `==` on the whole value would still pass if two
        // fields were swapped in *both* the encoder and the decoder.
        #expect(decoded.idempotenceVerbs == ["normalize"])
        #expect(decoded.commutativityVerbs == ["union"])
        #expect(decoded.antiCommutativityVerbs == ["subtract"])
        #expect(decoded.monotonicityVerbs == ["depth"])
        #expect(decoded.inverseElementVerbs == ["negate"])
        #expect(decoded.compositionVerbs == ["advance"])
        #expect(decoded.dualStyleNamePairs.first?.nonMutating == "sorted")
        #expect(decoded.registeredGenerators["YAMLConfig"]?.imports == ["Yams"])
    }

    /// Decoding is tolerant of a missing key — every field is
    /// `decodeIfPresent`-with-default — which is what lets an older
    /// `vocabulary.json` keep working. Pinned because that tolerance is also
    /// what makes a dropped `encode` line invisible: the two behaviours are the
    /// same mechanism seen from opposite sides.
    @Test("Vocabulary decodes an empty object to the default vocabulary")
    func vocabularyDecodesEmptyObject() throws {
        let decoded = try JSONDecoder().decode(Vocabulary.self, from: Data("{}".utf8))
        #expect(decoded == Vocabulary())
    }
}
