import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("IdentityElementTemplate — pair construction + signal score")
struct IdentityElementTemplatePairTests {

    @Test("Binary op + same-typed identity constant scores 70 (Likely) by construction")
    func pairScoresSeventyByConstruction() throws {
        let pair = makeIdentityElementPair(
            opName: "merge",
            paramTypes: ("IntSet", "IntSet"),
            returnType: "IntSet",
            identityName: "empty",
            identityType: "IntSet"
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(for: pair))
        // 30 type + 40 identity-element naming = 70 → Likely.
        #expect(suggestion.score.total == 70)
        #expect(suggestion.score.tier == .likely)
    }

    @Test("Empty-seed signal adds 20 when the op appears in opsWithIdentitySeed")
    func emptySeedSignalPromotesToStrong() throws {
        let pair = makeIdentityElementPair(
            opName: "merge",
            paramTypes: ("IntSet", "IntSet"),
            returnType: "IntSet",
            identityName: "empty",
            identityType: "IntSet"
        )
        let suggestion = try #require(
            IdentityElementTemplate.suggest(for: pair, opsWithIdentitySeed: ["merge"])
        )
        // 30 + 40 + 20 = 90 → Strong.
        #expect(suggestion.score.total == 90)
        #expect(suggestion.score.tier == .strong)
        let line = suggestion.explainability.whySuggested.first { $0.contains("empty-seed") }
        #expect(line == "Accumulator-with-empty-seed: 'merge' used in .reduce(<identity-shape>, op) (+20)")
    }

    @Test("Empty-seed set without the op's name doesn't fire the signal")
    func emptySeedSignalMissWhenOpNameAbsent() throws {
        let pair = makeIdentityElementPair(
            opName: "merge",
            paramTypes: ("IntSet", "IntSet"),
            returnType: "IntSet",
            identityName: "empty",
            identityType: "IntSet"
        )
        let suggestion = try #require(
            IdentityElementTemplate.suggest(for: pair, opsWithIdentitySeed: ["other"])
        )
        #expect(suggestion.score.total == 70)
    }

    @Test("Non-deterministic body in op suppresses regardless of identity match")
    func nonDeterministicVetoSuppresses() {
        let pair = makeIdentityElementPair(
            opName: "merge",
            paramTypes: ("IntSet", "IntSet"),
            returnType: "IntSet",
            identityName: "empty",
            identityType: "IntSet",
            opBodySignals: BodySignals(
                hasNonDeterministicCall: true,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: ["UUID"]
            )
        )
        #expect(IdentityElementTemplate.suggest(for: pair) == nil)
    }
}
