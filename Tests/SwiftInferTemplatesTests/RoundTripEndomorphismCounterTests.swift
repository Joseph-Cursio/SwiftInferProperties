import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// Two endomorphisms are not an inverse pair.
///
/// `T -> T` paired with `T -> T` is not opposite-typed — it is two functions over one type,
/// and `g(f(x)) == x` is false for almost any such couple. The bare type-symmetry signal
/// cannot tell them apart, which makes it combinatorial: every `(String) -> String` helper
/// in a corpus pairs with every other.
///
/// **Measured before shipping**, on two corpora with a systematic sample read at each step:
///
/// | corpus | round-trip before → after |
/// |---|---|
/// | this repo, private seeded | 438 → 92 |
/// | this repo, baseline | 53 → 1 |
/// | FoundationEssentials | 142 → 53, keeping all 5 Strong + 5 Likely |
///
/// Every same-type pair sampled was false on **both** corpora, which is the important part:
/// `sanitizeForFileName` × `stripGenericParameters` here, and on Foundation
/// `index(afterUnicodeScalar:)` × `index(afterRun:)` (both *after*) and
/// `deletingLastPathComponent()` × `deletingPathExtension()` (both *deleting*) — 14 of 14
/// in the dropped sample. So this raised precision where round-trip already worked, not
/// only where it was broken.
@Suite("Round-trip — two endomorphisms are not an inverse pair")
struct RoundTripEndomorphismCounterTests {

    // MARK: - Suppressed: nothing but the shape

    @Test("a shape-only same-type pair is suppressed", arguments: [
        ("sanitizeForFileName", "stripGenericParameters"),
        ("bareTypeName", "stripParameterLabels"),
        ("quoted", "excerpt")
    ])
    func shapeOnlySameTypePairSuppressed(forward: String, reverse: String) {
        let pair = makeRoundTripPair(
            forwardName: forward,
            reverseName: reverse,
            forwardParam: "String",
            forwardReturn: "String"
        )
        #expect(RoundTripTemplate.suggest(for: pair) == nil)
    }

    @Test("the counter cancels type-symmetry exactly, rather than discounting it")
    func counterCancelsTypeSymmetry() throws {
        // -30 against +30. The claim type-symmetry makes — "these two signatures oppose" —
        // is simply untrue of two endomorphisms, so the honest arithmetic takes it back.
        let signals = RoundTripTemplate.accumulatedSignals(
            for: makeRoundTripPair(
                forwardName: "quoted",
                reverseName: "excerpt",
                forwardParam: "String",
                forwardReturn: "String"
            ),
            vocabulary: .empty,
            inheritedTypesByName: [:],
            carrierKindResolver: nil
        )
        let counter = try #require(signals.first { $0.kind == .endomorphismRoundTripPair })
        #expect(counter.weight == -30)
        #expect(!counter.isVeto, "the shape is real; it is the OPPOSITION that is not")
        let symmetry = try #require(signals.first { $0.kind == .typeSymmetrySignature })
        #expect(counter.weight == -symmetry.weight)
        #expect(Score(signals: signals).total == 0)
    }

    // MARK: - Not suppressed: opposite-typed pairs are the real shape

    @Test("an opposite-typed pair is untouched — that IS the round-trip shape")
    func oppositeTypedPairUntouched() throws {
        let pair = makeRoundTripPair(
            forwardName: "transform",
            reverseName: "untransform",
            forwardParam: "MyType",
            forwardReturn: "Data"
        )
        let suggestion = try #require(RoundTripTemplate.suggest(for: pair))
        #expect(suggestion.score.total == 30)
        #expect(
            !suggestion.score.signals.contains { $0.kind == .endomorphismRoundTripPair }
        )
    }

    // MARK: - The four channels that vouch for a same-type pair

    /// Each of these was added because a test caught a true positive being deleted, which is
    /// the argument for keeping those tests. A base64 `encode`/`decode` really is a same-type
    /// round-trip; so is `exp`/`log` on `Complex`.
    @Test("a CURATED inverse name pair survives on the same type")
    func curatedNameSurvives() throws {
        let pair = makeRoundTripPair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "String",
            forwardReturn: "String"
        )
        let suggestion = try #require(RoundTripTemplate.suggest(for: pair))
        #expect(!suggestion.score.signals.contains { $0.kind == .endomorphismRoundTripPair })
    }

    @Test("a canonical MATH inverse pair survives — the second curated channel")
    func canonicalMathInverseSurvives() {
        // `MathForwardFunctions.canonicalInversePairs` is a different list from
        // `curatedInversePairs`, and checking only the latter destroyed this pair.
        let pair = makeRoundTripPair(
            forwardName: "exp",
            reverseName: "log",
            forwardParam: "Complex",
            forwardReturn: "Complex"
        )
        let signals = RoundTripTemplate.accumulatedSignals(
            for: pair,
            vocabulary: .empty,
            inheritedTypesByName: [:],
            carrierKindResolver: nil
        )
        #expect(!signals.contains { $0.kind == .endomorphismRoundTripPair })
    }

    @Test("an explicit @discoverable group survives — a user declaration outranks a shape")
    func discoverableGroupSurvives() {
        let pair = makeRoundTripPair(
            forwardName: "wibble",
            reverseName: "wobble",
            forwardParam: "Token",
            forwardReturn: "Token",
            forwardGroup: "codec",
            reverseGroup: "codec"
        )
        let signals = RoundTripTemplate.accumulatedSignals(
            for: pair,
            vocabulary: .empty,
            inheritedTypesByName: [:],
            carrierKindResolver: nil
        )
        #expect(!signals.contains { $0.kind == .endomorphismRoundTripPair })
    }

    @Test("a project-vocabulary inverse pair survives")
    func projectVocabularySurvives() {
        let pair = makeRoundTripPair(
            forwardName: "shroud",
            reverseName: "unshroud",
            forwardParam: "Token",
            forwardReturn: "Token"
        )
        let vocabulary = Vocabulary(inversePairs: [.init(forward: "shroud", reverse: "unshroud")])
        let signals = RoundTripTemplate.accumulatedSignals(
            for: pair,
            vocabulary: vocabulary,
            inheritedTypesByName: [:],
            carrierKindResolver: nil
        )
        #expect(!signals.contains { $0.kind == .endomorphismRoundTripPair })
    }

    // MARK: - What this does NOT claim

    /// A "reciprocal labels" channel was tried and removed. `minimumCapacity(forScale:)` ↔
    /// `scale(forCapacity:)` names its counterpart in both directions, which looks like
    /// inverse evidence and is not: `DomainMarkerLabels.curated` contains exactly `forScale`
    /// and `forCapacity`, added in cycle-11 to PENALISE these pairs as "shapes that pass
    /// typeSymmetry but cross domains semantically". Reciprocal labels mark a cross-domain
    /// *conversion*. This pins that the two counters agree rather than fight.
    @Test("reciprocal domain-marker labels do NOT rescue a same-type pair")
    func domainMarkerLabelsDoNotRescue() {
        let pair = makeRoundTripPair(
            forwardName: "minimumCapacity",
            reverseName: "scale",
            forwardParam: "Int",
            forwardReturn: "Int",
            forwardLabel: "forScale",
            reverseLabel: "forCapacity"
        )
        #expect(RoundTripTemplate.suggest(for: pair) == nil)
    }
}
