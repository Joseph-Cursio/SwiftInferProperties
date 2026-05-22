import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("Round-trip cross-type counter-signal — V1.4.3b calibration tuning")
struct CrossTypeRoundTripTests {

    // MARK: - Fixtures

    private static func unary(
        name: String,
        domain: String,
        codomain: String,
        containingTypeName: String?,
        discoverableGroup: String? = nil
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: nil, internalName: "x", typeText: domain, isInout: false)],
            returnTypeText: codomain,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "test.swift", line: 1, column: 1),
            containingTypeName: containingTypeName,
            bodySignals: .empty,
            discoverableGroup: discoverableGroup
        )
    }

    // MARK: - Same-type pair → unaffected

    @Test("Same-type round-trip on Doc accepts; no cross-type counter-signal")
    func sameTypeAccepts() throws {
        let forward = Self.unary(name: "encode", domain: "Doc", codomain: "Data", containingTypeName: "Doc")
        let reverse = Self.unary(name: "decode", domain: "Data", codomain: "Doc", containingTypeName: "Doc")
        let pair = FunctionPair(forward: forward, reverse: reverse)
        let suggestion = try #require(RoundTripTemplate.suggest(for: pair))
        #expect(!suggestion.score.signals.contains { $0.kind == .crossTypeRoundTripPair })
    }

    @Test("Cross-extension on same type — both extensions on Doc — passes")
    func crossExtensionSameTypePasses() throws {
        // Both functions live on `Doc` but in different files / extensions.
        // Both record `containingTypeName == "Doc"`; the cross-type rule
        // doesn't fire.
        let forward = Self.unary(name: "encode", domain: "Doc", codomain: "Data", containingTypeName: "Doc")
        let reverse = Self.unary(name: "decode", domain: "Data", codomain: "Doc", containingTypeName: "Doc")
        let pair = FunctionPair(forward: forward, reverse: reverse)
        let suggestion = try #require(RoundTripTemplate.suggest(for: pair))
        #expect(!suggestion.score.signals.contains { $0.kind == .crossTypeRoundTripPair })
    }

    // MARK: - Free-function (nil container) pair → unaffected

    @Test("Top-level free-function round-trip pair is exempt (nil == nil)")
    func freeFunctionPairExempt() throws {
        // Both `containingTypeName == nil` → both functions are top-level.
        // The rule should NOT fire — `nil == nil` is the same scope.
        let forward = Self.unary(name: "encode", domain: "Doc", codomain: "Data", containingTypeName: nil)
        let reverse = Self.unary(name: "decode", domain: "Data", codomain: "Doc", containingTypeName: nil)
        let pair = FunctionPair(forward: forward, reverse: reverse)
        let suggestion = try #require(RoundTripTemplate.suggest(for: pair))
        #expect(!suggestion.score.signals.contains { $0.kind == .crossTypeRoundTripPair })
    }

    // MARK: - Cross-type pair → suppressed

    @Test("Cross-type round-trip pair — forward on `A`, reverse on `B` — suppressed (returns nil)")
    func crossTypeSuppressed() {
        // Different containing types — analogous to the swift-algorithms
        // `AdjacentPairsCollection.index(after:)` paired with
        // `Chain2Sequence.index(before:)` case. Score drops 30 → 5 = Suppressed,
        // so `suggest` returns nil.
        let forward = Self.unary(name: "after", domain: "Index", codomain: "Index", containingTypeName: "TypeA")
        let reverse = Self.unary(name: "before", domain: "Index", codomain: "Index", containingTypeName: "TypeB")
        let pair = FunctionPair(forward: forward, reverse: reverse)
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion == nil, "cross-type round-trip should be suppressed")
    }

    @Test("Cross-type pair where one side is nil (free function) — also suppressed")
    func crossTypeMixedContainerSuppressed() {
        // `nil` (free function) vs named container = different scopes.
        // Should still fire the counter-signal. Uses non-curated names
        // (`transform`/`untransform`) so the curated +40 doesn't lift
        // the score back above the suppression threshold.
        let forward = Self.unary(
            name: "transform", domain: "Doc", codomain: "Data", containingTypeName: nil
        )
        let reverse = Self.unary(
            name: "untransform", domain: "Data", codomain: "Doc", containingTypeName: "DocCodec"
        )
        let pair = FunctionPair(forward: forward, reverse: reverse)
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion == nil, "free-function paired with member-of-type should suppress")
    }

    // MARK: - @Discoverable(group:) exemption

    @Test("Cross-type pair sharing @Discoverable(group:) is exempt — user opt-in overrides")
    func sharedDiscoverableGroupExempts() throws {
        // Mirrors the swift-infer fixture (DiscoverableGroupIntegrationTests):
        // `Encoder.encode` + `Decoder.decode` both tagged `@Discoverable(group: "codec")`.
        // Different containing types but the user has explicitly grouped them —
        // the +35 discoverableAnnotation signal already captures the positive
        // evidence; the -25 cross-type signal would double-count.
        let forward = Self.unary(
            name: "encode", domain: "Doc", codomain: "Data",
            containingTypeName: "Encoder", discoverableGroup: "codec"
        )
        let reverse = Self.unary(
            name: "decode", domain: "Data", codomain: "Doc",
            containingTypeName: "Decoder", discoverableGroup: "codec"
        )
        let pair = FunctionPair(forward: forward, reverse: reverse)
        let suggestion = try #require(RoundTripTemplate.suggest(for: pair))
        #expect(!suggestion.score.signals.contains { $0.kind == .crossTypeRoundTripPair })
    }

    @Test("Cross-type pair with mismatched @Discoverable(group:) does NOT exempt")
    func mismatchedDiscoverableGroupDoesNotExempt() {
        // Different groups — the user did not opt in to pairing these.
        // The cross-type rule should still fire.
        let forward = Self.unary(
            name: "transform", domain: "Doc", codomain: "Data",
            containingTypeName: "Encoder", discoverableGroup: "codec"
        )
        let reverse = Self.unary(
            name: "untransform", domain: "Data", codomain: "Doc",
            containingTypeName: "Decoder", discoverableGroup: "queue"
        )
        let pair = FunctionPair(forward: forward, reverse: reverse)
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion == nil, "mismatched group should still suppress")
    }

    @Test("Cross-type pair where only one side has @Discoverable(group:) does NOT exempt")
    func oneSidedDiscoverableGroupDoesNotExempt() {
        // Asymmetric tagging — the user only tagged one half. Ambiguous
        // intent; the rule still fires (conservative posture per PRD §3.5).
        let forward = Self.unary(
            name: "transform", domain: "Doc", codomain: "Data",
            containingTypeName: "Encoder", discoverableGroup: "codec"
        )
        let reverse = Self.unary(
            name: "untransform", domain: "Data", codomain: "Doc",
            containingTypeName: "Decoder", discoverableGroup: nil
        )
        let pair = FunctionPair(forward: forward, reverse: reverse)
        let suggestion = RoundTripTemplate.suggest(for: pair)
        #expect(suggestion == nil, "one-sided tag should still suppress")
    }

    @Test("Cross-type counter-signal magnitude is -25 (drops Score 30 → 5)")
    func counterSignalMagnitude() {
        // White-box: build a pair that surfaces but verify the counter-
        // signal weight is exactly -25. Use a named-pair scenario where
        // we can read the score before suppression filters the result.
        let forward = Self.unary(name: "encode", domain: "Doc", codomain: "Data", containingTypeName: "TypeA")
        let reverse = Self.unary(name: "decode", domain: "Data", codomain: "Doc", containingTypeName: "TypeB")
        let pair = FunctionPair(forward: forward, reverse: reverse)
        // Score = 30 (typeSymmetry) + 40 (curated encode/decode) - 25 (crossType) = 45 → Likely.
        // The named curated pair lifts above suppression, but the cross-type
        // signal is still present and weighted -25.
        let suggestion = RoundTripTemplate.suggest(for: pair)
        guard let suggestion else {
            Issue.record("expected suggestion to surface — Likely tier")
            return
        }
        let crossType = suggestion.score.signals.first { $0.kind == .crossTypeRoundTripPair }
        #expect(crossType != nil)
        #expect(crossType?.weight == -25)
    }
}
