// Hand-written oracles for the V1 toy of `scripts/predicate_outcome_reach.py validate`.
//
// Each test replays one stub's draws WITHOUT the stub: its four seed words and its generator text
// are copied verbatim from the stub `swift-infer` emitted at `fef2971d`, a plain `Xoshiro(seed:)`
// loop draws from them, and the subject is called directly. No wrap, no clone and no parse of a
// stub is involved, so `validate` compares two independent readings bit for bit.
//
// It replays the clone's process, not only its first test: 100 trials (`law`), 100 more from a
// fresh generator on the same seed (`again`), then 1,000 (`scale`), in that order and in one
// process, so a stateful subject sees the history the clone's subject sees. Every answer is one
// `OPROBE|<subject>|<0|1>` line after an `OBEGIN|<subject>|<pass>` line, written through the reach
// probe helper. A draw on which the subject would trap or spin is never handed to it:
// `OSTOP|<subject>|<pass>|<k>` says the clone must stop at its k-th call there, and the oracle stops.
//
// Copied into the census target by `validate`; never compiled from here.
import Foundation
import PropertyBased
import Testing
@testable import PredicateReachToy

private typealias SeedWords = (UInt64, UInt64, UInt64, UInt64)

/// The clone's three tests, in the clone's order.
private let oraclePasses: [(name: String, trials: Int)] = [("law", 100), ("again", 100), ("scale", 1_000)]

@MainActor
private func replay<Input: Sendable>(
    _ subject: String,
    seed: SeedWords,
    draw: (inout Xoshiro) -> Input,
    stopsBefore stops: (Input) -> Bool = { _ in false },
    answer: @MainActor (Input) async -> Bool
) async {
    for pass in oraclePasses {
        __reachOracle("OBEGIN|\(subject)|\(pass.name)")
        var oracleRNG = Xoshiro(seed: seed)
        for call in 1 ... pass.trials {
            let input = draw(&oracleRNG)
            if stops(input) {
                __reachOracle("OSTOP|\(subject)|\(pass.name)|\(call)")
                return
            }
            let answered = await answer(input)
            __reachOracle("OPROBE|\(subject)|\(answered ? 1 : 0)")
        }
    }
}

struct PredicateReachOracles {

    // Verbatim from `PointIsRightOfPredicateTests`.
    nonisolated private static let isRightOfGenerator = zip(Gen<Int>.int(), Gen<Int>.int()).map { drawn in
        Point(xCoord: drawn.0, yCoord: drawn.1)
    }

    // Verbatim from `LayoutTrimsLeadingPredicateTests`.
    nonisolated private static let trimsLeadingGenerator = Gen.frequency(
        (
            3.0,
            Gen.frequency(
                (2.0, Gen<Character>.letterOrNumber.string(of: 0...8)),
                (1.0, Gen<String?>.element(of: [" "] as [String]).compactMap(\.self)),
                (
                    1.0,
                    zip(
                        zip(
                            Gen<Character>.letterOrNumber.string(of: 0...4),
                            Gen<String?>.element(of: [" "] as [String]).compactMap(\.self)
                        ).map { $0 + $1 },
                        Gen<Character>.letterOrNumber.string(of: 0...4)
                    ).map { $0 + $1 }
                )
            )
        ),
        (
            3.0,
            Gen<String?>
                .element(
                    of: [
                        "", " ", "\n", "\t", "[", "]", "[[", "]]", "[[a]]", "[[a|b]]", "{", "}", "<", ">", "(", ")",
                        "\"", "'", "\\", "|", "&", ";", "%", "$", "\u{0}", "\u{7F}"
                    ] as [String]
                )
                .compactMap(\.self)
        ),
        (
            2.0,
            Gen<String?>
                .element(
                    of: [
                        "", " ", "\n", "\t", "[", "]", "[[", "]]", "[[a]]", "[[a|b]]", "{", "}", "<", ">", "(", ")",
                        "\"", "'", "\\", "|", "&", ";", "%", "$", "\u{0}", "\u{7F}"
                    ] as [String]
                )
                .compactMap(\.self)
                .map { $0 + $0 }
        ),
        (1.0, Gen<Character>.latin1.string(of: 0...24)),
        (1.0, Gen<Character>.ascii.string(of: 0...120))
    )

    // Verbatim from `MatcherMatchesPrefixPredicateTests`.
    nonisolated private static let matchesPrefixGenerator = Gen.frequency(
        (
            3.0,
            Gen.frequency(
                (2.0, Gen<Character>.letterOrNumber.string(of: 0...8)),
                (1.0, Gen<String?>.element(of: ["ab"] as [String]).compactMap(\.self)),
                (
                    1.0,
                    zip(
                        zip(
                            Gen<Character>.letterOrNumber.string(of: 0...4),
                            Gen<String?>.element(of: ["ab"] as [String]).compactMap(\.self)
                        ).map { $0 + $1 },
                        Gen<Character>.letterOrNumber.string(of: 0...4)
                    ).map { $0 + $1 }
                )
            )
        ),
        (
            3.0,
            Gen<String?>
                .element(
                    of: [
                        "", " ", "\n", "\t", "[", "]", "[[", "]]", "[[a]]", "[[a|b]]", "{", "}", "<", ">", "(", ")",
                        "\"", "'", "\\", "|", "&", ";", "%", "$", "\u{0}", "\u{7F}"
                    ] as [String]
                )
                .compactMap(\.self)
        ),
        (
            2.0,
            Gen<String?>
                .element(
                    of: [
                        "", " ", "\n", "\t", "[", "]", "[[", "]]", "[[a]]", "[[a|b]]", "{", "}", "<", ">", "(", ")",
                        "\"", "'", "\\", "|", "&", ";", "%", "$", "\u{0}", "\u{7F}"
                    ] as [String]
                )
                .compactMap(\.self)
                .map { $0 + $0 }
        ),
        (1.0, Gen<Character>.latin1.string(of: 0...24)),
        (1.0, Gen<Character>.ascii.string(of: 0...120))
    )

    // Verbatim from `RulesConsumesPrefixPredicateTests`.
    nonisolated private static let consumesPrefixGenerator = Gen.frequency(
        (
            3.0,
            Gen.frequency(
                (2.0, Gen<Character>.letterOrNumber.string(of: 0...8)),
                (1.0, Gen<String?>.element(of: ["a"] as [String]).compactMap(\.self)),
                (
                    1.0,
                    zip(
                        zip(
                            Gen<Character>.letterOrNumber.string(of: 0...4),
                            Gen<String?>.element(of: ["a"] as [String]).compactMap(\.self)
                        ).map { $0 + $1 },
                        Gen<Character>.letterOrNumber.string(of: 0...4)
                    ).map { $0 + $1 }
                )
            )
        ),
        (
            3.0,
            Gen<String?>
                .element(
                    of: [
                        "", " ", "\n", "\t", "[", "]", "[[", "]]", "[[a]]", "[[a|b]]", "{", "}", "<", ">", "(", ")",
                        "\"", "'", "\\", "|", "&", ";", "%", "$", "\u{0}", "\u{7F}"
                    ] as [String]
                )
                .compactMap(\.self)
        ),
        (
            2.0,
            Gen<String?>
                .element(
                    of: [
                        "", " ", "\n", "\t", "[", "]", "[[", "]]", "[[a]]", "[[a|b]]", "{", "}", "<", ">", "(", ")",
                        "\"", "'", "\\", "|", "&", ";", "%", "$", "\u{0}", "\u{7F}"
                    ] as [String]
                )
                .compactMap(\.self)
                .map { $0 + $0 }
        ),
        (1.0, Gen<Character>.latin1.string(of: 0...24)),
        (1.0, Gen<Character>.ascii.string(of: 0...120))
    )

    // Verbatim from `IsBlankLinePredicateTests`.
    nonisolated private static let isBlankLineGenerator = Gen.frequency(
        (
            3.0,
            Gen.frequency(
                (2.0, Gen<Character>.letterOrNumber.string(of: 0...8)),
                (1.0, Gen<String?>.element(of: [" "] as [String]).compactMap(\.self)),
                (
                    1.0,
                    zip(
                        zip(
                            Gen<Character>.letterOrNumber.string(of: 0...4),
                            Gen<String?>.element(of: [" "] as [String]).compactMap(\.self)
                        ).map { $0 + $1 },
                        Gen<Character>.letterOrNumber.string(of: 0...4)
                    ).map { $0 + $1 }
                )
            )
        ),
        (
            3.0,
            Gen<String?>
                .element(
                    of: [
                        "", " ", "\n", "\t", "[", "]", "[[", "]]", "[[a]]", "[[a|b]]", "{", "}", "<", ">", "(", ")",
                        "\"", "'", "\\", "|", "&", ";", "%", "$", "\u{0}", "\u{7F}"
                    ] as [String]
                )
                .compactMap(\.self)
        ),
        (
            2.0,
            Gen<String?>
                .element(
                    of: [
                        "", " ", "\n", "\t", "[", "]", "[[", "]]", "[[a]]", "[[a|b]]", "{", "}", "<", ">", "(", ")",
                        "\"", "'", "\\", "|", "&", ";", "%", "$", "\u{0}", "\u{7F}"
                    ] as [String]
                )
                .compactMap(\.self)
                .map { $0 + $0 }
        ),
        (1.0, Gen<Character>.latin1.string(of: 0...24)),
        (1.0, Gen<Character>.ascii.string(of: 0...120))
    )

    // Verbatim from `RulesHasControlCharactersPredicateTests`.
    nonisolated private static let hasControlCharactersGenerator = Gen.frequency(
        (3.0, Gen<Character>.letterOrNumber.string(of: 0...8)),
        (
            3.0,
            Gen<String?>
                .element(
                    of: [
                        "", " ", "\n", "\t", "[", "]", "[[", "]]", "[[a]]", "[[a|b]]", "{", "}", "<", ">", "(", ")",
                        "\"", "'", "\\", "|", "&", ";", "%", "$", "\u{0}", "\u{7F}"
                    ] as [String]
                )
                .compactMap(\.self)
        ),
        (
            2.0,
            Gen<String?>
                .element(
                    of: [
                        "", " ", "\n", "\t", "[", "]", "[[", "]]", "[[a]]", "[[a|b]]", "{", "}", "<", ">", "(", ")",
                        "\"", "'", "\\", "|", "&", ";", "%", "$", "\u{0}", "\u{7F}"
                    ] as [String]
                )
                .compactMap(\.self)
                .map { $0 + $0 }
        ),
        (1.0, Gen<Character>.latin1.string(of: 0...24)),
        (1.0, Gen<Character>.ascii.string(of: 0...120))
    )

    @Test @MainActor func isEvenOracle() async {
        await replay(
            "isEven",
            seed: (0x9C9C98B3B07C4338, 0x294DEF914F4AFAAD, 0xCC7AC966AEC41B04, 0xC489C2F632059409),
            draw: { rng in (Gen<Int>.int()).run(using: &rng) }
        ) { value in Rules.isEven(value) }
    }

    @Test @MainActor func isRightOfOracle() async {
        await replay(
            "isRightOf",
            seed: (0xFFC75A11D38F79F4, 0x68AF390FD7D6AC7F, 0xF4B0D928035F0D85, 0x0EB2CB970F16E48A),
            draw: { rng in
                let arg0 = Self.isRightOfGenerator.run(using: &rng)
                let arg1 = Self.isRightOfGenerator.run(using: &rng)
                return (arg0, arg1)
            }
        ) { args in args.0.isRightOf(args.1) }
    }

    @Test @MainActor func isWithinOracle() async {
        await replay(
            "isWithin",
            seed: (0xB9FC1F805D0C986A, 0x57B6DA2E3371CC40, 0x8A512A429F7A430A, 0xEE30555C023E506F),
            draw: { rng in
                let arg0 = (Gen<Int>.int()).run(using: &rng)
                let arg1 = (Gen<Int>.int()).run(using: &rng)
                return (arg0, arg1)
            }
        ) { args in Rules.isWithin(args.0, limit: args.1) }
    }

    @Test @MainActor func isWideOracle() async {
        await replay(
            "isWide",
            seed: (0x5A52DCF59A877628, 0xFC6A40B2C0728622, 0xB1BEEBD22CAF99A8, 0x80321EE5E6BCDFA3),
            draw: { rng in (Gen<Int>.int()).run(using: &rng) }
        ) { value in Layout.isWide(value) }
    }

    @Test @MainActor func trimsLeadingOracle() async {
        await replay(
            "trimsLeading",
            seed: (0x5188698263F91CFE, 0x830A34253E1F7A8A, 0x320523DAD58E69C2, 0xAC76736076CE72D0),
            draw: { rng in Self.trimsLeadingGenerator.run(using: &rng) }
        ) { value in
            var inout0 = value
            return Layout.trimsLeading(&inout0)
        }
    }

    @Test @MainActor func matchesPrefixOracle() async {
        await replay(
            "matchesPrefix",
            seed: (0xB3D0D806260EDE00, 0x260DF06BB0A01922, 0xE715D04CD0C4A513, 0x58EAAC334F62B4DD),
            draw: { rng in Self.matchesPrefixGenerator.run(using: &rng) }
        ) { value in Matcher().matchesPrefix(value) }
    }

    @Test @MainActor func consumesPrefixOracle() async {
        await replay(
            "consumesPrefix",
            seed: (0xC174C3434FE0CF82, 0xF93B480496942FDC, 0x12E8933EE822C84A, 0xFCD88532DA8581BC),
            draw: { rng in Self.consumesPrefixGenerator.run(using: &rng) }
        ) { value in
            var inout0 = value
            return Rules.consumesPrefix(&inout0)
        }
    }

    @Test @MainActor func isBlankLineOracle() async {
        await replay(
            "isBlankLine",
            seed: (0x18DB0ACA55DD25B8, 0xB6A0D5E09A5ACBB7, 0xF098AD72DBEFD94A, 0xFFC8EB8D9222ED53),
            draw: { rng in Self.isBlankLineGenerator.run(using: &rng) }
        ) { value in isBlankLine(value) }
    }

    @Test @MainActor func hasControlCharactersOracle() async {
        await replay(
            "hasControlCharacters",
            seed: (0x7CDB355A7C856E89, 0x3ABE5FDF8036664F, 0x7C3E68A14589CD20, 0xB023FDB9296BF970),
            draw: { rng in Self.hasControlCharactersGenerator.run(using: &rng) }
        ) { value in Rules.hasControlCharacters(value) }
    }

    @Test @MainActor func isMagicOracle() async {
        await replay(
            "isMagic",
            seed: (0x2388F1D58808A2F6, 0x2BF47D98E8E3C421, 0xACAC83D1ED4A175D, 0x3FF518F878477E0A),
            draw: { rng in (Gen<Int>.int()).run(using: &rng) }
        ) { value in Rules.isMagic(value) }
    }

    @Test @MainActor func isRepresentableOracle() async {
        await replay(
            "isRepresentable",
            seed: (0x8183DED4F37141D1, 0xFABC4A1202242F33, 0xE22A91492224490F, 0xAF1F65BDD48F24B3),
            draw: { rng in (Gen<Int>.int()).run(using: &rng) }
        ) { value in Rules.isRepresentable(value) }
    }

    @Test @MainActor func isRareResidueOracle() async {
        await replay(
            "isRareResidue",
            seed: (0x8D95A934F6200D1D, 0x54CA093BB1D6698C, 0x8D1EFDDE83F18902, 0x6AC44C00415FFE6F),
            draw: { rng in (Gen<Int>.int()).run(using: &rng) }
        ) { value in Rules.isRareResidue(value) }
    }

    @Test @MainActor func indexesSmallTableOracle() async {
        await replay(
            "indexesSmallTable",
            seed: (0xB4293D3AE2DB3BB1, 0x6200EDCEE237FEF8, 0xCD331CC75AB7FD3E, 0x7F56658AC10F7098),
            draw: { rng in (Gen<Int>.int()).run(using: &rng) },
            stopsBefore: { value in !(0 ..< 3).contains(value) }
        ) { value in Rules.indexesSmallTable(value) }
    }

    @Test @MainActor func spinsForeverOracle() async {
        await replay(
            "spinsForever",
            seed: (0xAF65E8F981BA1010, 0xD3706BC99AB9D8FF, 0xC0BF6E44AF00E447, 0x5C572418D520A319),
            draw: { rng in (Gen<Int>.int()).run(using: &rng) },
            stopsBefore: { _ in true }
        ) { value in Faults.spinsForever(value) }
    }

    @Test @MainActor func trapsLateOracle() async {
        await replay(
            "trapsLate",
            seed: (0x7180397824D3877D, 0x0A059CB21D2DA867, 0x95E532C144298AB8, 0xAC95478BA48B9151),
            draw: { rng in (Gen<Int>.int()).run(using: &rng) },
            stopsBefore: { value in value == Faults.trapValue }
        ) { value in Faults.trapsLate(value) }
    }

    @Test @MainActor func spinsLateOracle() async {
        await replay(
            "spinsLate",
            seed: (0x91381B192D7CAC6D, 0xF2E02DF3E3B20264, 0xE7E8AD1443CF1DBF, 0xCDB3A435B783F042),
            draw: { rng in (Gen<Int>.int()).run(using: &rng) },
            stopsBefore: { value in value == Faults.spinValue }
        ) { value in Faults.spinsLate(value) }
    }

    @Test @MainActor func isFirstSightingOracle() async {
        await replay(
            "isFirstSighting",
            seed: (0x2DDD5039B5234428, 0x58816A42594612AD, 0x5F8460BDB0952ECB, 0x190A062A69AAF651),
            draw: { rng in (Gen<Int>.int()).run(using: &rng) }
        ) { value in Sightings.isFirstSighting(value) }
    }

    @Test @MainActor func firstOfFourIsEvenOracle() async {
        await replay(
            "firstOfFourIsEven",
            seed: (0xDB3959CFE50900F0, 0x31CF2351E1F4CC7E, 0x9C0EBB272FB1EE4E, 0xBD27307B53085ECA),
            draw: { rng in (Gen<Int>.int()).run(using: &rng) }
        ) { value in HashOrder.firstOfFourIsEven(value) }
    }

    @Test @MainActor func firstOfTwoIsAOracle() async {
        await replay(
            "firstOfTwoIsA",
            seed: (0x6E790EE83C1E7BD7, 0x147E5A9ADD58949F, 0xFAF516556E4183E2, 0x02ABE75454463FB2),
            draw: { rng in (Gen<Int>.int()).run(using: &rng) }
        ) { value in HashOrder.firstOfTwoIsA(value) }
    }

    @Test @MainActor func holdsOracle() async {
        await replay(
            "holds",
            seed: (0x29EEE02D4FB7DF42, 0xA5F8B3FC66629CB3, 0xCAF2032E30F64112, 0xF6204A3CFC6B52DE),
            draw: { rng in (Gen<Int>.int()).run(using: &rng) }
        ) { value in await Registry().holds(value) }
    }
}
