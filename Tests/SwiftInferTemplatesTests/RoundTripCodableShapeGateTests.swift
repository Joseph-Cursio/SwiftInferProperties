import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// V1.8.1 — round-trip Codable encoder/decoder shape gate.
// Split out of `AssumedKitCoveragePairTests.swift` for the SwiftLint
// 400-line file budget per the V1.7.1 split precedent.
// Existing V1.5.2 round-trip Codable veto tests stay in the primary
// file; this file owns only the V1.8.1 shape-gate surface.

@Suite("RoundTripTemplate — V1.8.1 Codable encoder/decoder shape gate")
struct RoundTripCodableShapeGateTests {

    @Test("V1.8.1 — `(T) -> T` user-inverse pair on Codable T does NOT veto (cycle-4 fix)")
    func userInversePairOnCodableTypeNoLongerVetoed() {
        // The cycle-4 false-positive case. Cycle-3+4 OrderedCollections had
        // 22 round-trip suggestions like `minimumCapacity(forScale:) ↔
        // scale(forCapacity:)` on `(Int) -> Int` — these are user-defined
        // inverse pairs *by intent*, not Codable round-trips. V1.7.1's
        // bake-in resolved Int as Codable, triggering the veto. V1.8.1
        // shape-gates the veto so `(T) -> T` pairs fall through.
        let pair = makeRoundTripPair(
            forwardName: "minimumCapacity",
            reverseName: "scale",
            forwardParam: "Int",
            forwardReturn: "Int"
        )
        //
        // Asserted on the SIGNALS rather than on a surfaced suggestion, and the change is
        // deliberate. This pair no longer surfaces — the endomorphism counter-signal suppresses
        // bare `(Int) -> Int` × `(Int) -> Int` with nothing vouching for it — but that is a
        // *different* verdict from the Codable veto, and this test owns only the veto. Checking
        // `suggest(...) != nil` conflated "the veto did not fire" with "something surfaced",
        // which is exactly the conflation that let the assertion pass for the wrong reason.
        //
        // And the suppression agrees with a decision this project already made: cycle-11 added
        // `forScale`/`forCapacity` to `DomainMarkerLabels.curated` to penalise the *labelled*
        // form of this very pair — "shapes that pass typeSymmetry but cross domains
        // semantically." Capacity and scale are different quantities. The comment above calls
        // them "inverse pairs by intent"; cycle-11 measured them and disagreed.
        let signals = RoundTripTemplate.accumulatedSignals(
            for: pair,
            vocabulary: .empty,
            inheritedTypesByName: makeInheritedIndex("Int", conformances: ["Codable", "Numeric"]),
            carrierKindResolver: nil
        )
        #expect(!signals.contains { $0.kind == .protocolCoveredProperty })
        // Pin the reason it is suppressed, so a future change to either counter is visible here.
        #expect(signals.contains { $0.kind == .endomorphismRoundTripPair })
    }

    @Test("V1.8.1 — `(T) -> Data` ↔ `(Data) -> T` Codable shape with T Codable still vetoes")
    func codableEncoderDecoderShapeStillVetoes() {
        // The true Codable round-trip surface — should still suppress
        // because the kit's `checkCodablePropertyLaws` covers this pair.
        let pair = makeRoundTripPair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "Doc",
            forwardReturn: "Data"
        )
        let result = RoundTripTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("Doc", conformances: ["Codable"])
        )
        #expect(result == nil, "Codable encoder/decoder shape should still be vetoed")
    }

    @Test("V1.8.1 — `(T) -> String` ↔ `(String) -> T` Codable shape with T Codable still vetoes")
    func stringCodecShapeStillVetoes() {
        // String is the second curated codec format. JSON-string
        // round-trips (encode-as-String / decode-from-String) are
        // legitimate Codable surfaces.
        let pair = makeRoundTripPair(
            forwardName: "serialize",
            reverseName: "deserialize",
            forwardParam: "User",
            forwardReturn: "String"
        )
        let result = RoundTripTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("User", conformances: ["Codable"])
        )
        #expect(result == nil, "String-codec encoder/decoder shape should still be vetoed")
    }

    @Test("V1.8.1 — Decoder-as-forward orientation `(Data) -> T` ↔ `(T) -> Data` still vetoes")
    func decoderAsForwardStillVetoes() {
        // FunctionPairing doesn't canonicalize encoder-as-forward —
        // either orientation can land. The shape gate has to match
        // both orientations.
        let pair = makeRoundTripPair(
            forwardName: "decode",
            reverseName: "encode",
            forwardParam: "Data",
            forwardReturn: "Doc"
        )
        let result = RoundTripTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("Doc", conformances: ["Codable"])
        )
        #expect(result == nil, "Decoder-as-forward orientation should still be vetoed")
    }

    @Test("V1.8.1 — `(T) -> Data` shape on non-Codable T does NOT veto (existing behavior)")
    func codableShapeOnNonCodableTypeStillNotVetoed() throws {
        // Existing V1.5.2 behavior: even with the shape gate, the
        // veto requires the carrier type to actually conform to
        // Codable. Custom domain types fall through.
        let pair = makeRoundTripPair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "Doc",
            forwardReturn: "Data"
        )
        let suggestion = try #require(RoundTripTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("Doc", conformances: ["Equatable", "Sendable"])
        ))
        #expect(!suggestion.score.signals.contains { $0.kind == .protocolCoveredProperty })
    }

    @Test("V1.8.1 — `(T) -> U` non-codec shape on Codable T does NOT veto")
    func nonCodecShapeOnCodableTypeNotVetoed() throws {
        // E.g., a `(User) -> Token` pair paired with `(Token) -> User`
        // — both User and Token are Codable but neither is in the
        // codec set. The shape gate falls through.
        let pair = makeRoundTripPair(
            forwardName: "tokenize",
            reverseName: "untokenize",
            forwardParam: "User",
            forwardReturn: "Token"
        )
        let suggestion = try #require(RoundTripTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("User", conformances: ["Codable"])
        ))
        #expect(!suggestion.score.signals.contains { $0.kind == .protocolCoveredProperty })
    }

    @Test("V1.8.1 — `(Data) -> Data` compression-shape pair does NOT veto")
    func dataToDataCompressionShapeNotVetoed() throws {
        // Both sides are codec types — the shape gate requires the
        // round-tripped T to be a *non-codec* type. `(Data) -> Data`
        // is naturally a compression / encryption / hashing pair, not
        // a Codable round-trip. Falls through unsuppressed even
        // though Data is Codable.
        let pair = makeRoundTripPair(
            forwardName: "compress",
            reverseName: "decompress",
            forwardParam: "Data",
            forwardReturn: "Data"
        )
        let suggestion = try #require(RoundTripTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("Data", conformances: ["Codable"])
        ))
        #expect(!suggestion.score.signals.contains { $0.kind == .protocolCoveredProperty })
    }
}
