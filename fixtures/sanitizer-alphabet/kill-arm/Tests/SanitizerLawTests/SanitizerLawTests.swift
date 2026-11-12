// #672's kill arm (`docs/plans/sanitizer-alphabet-census-scope.md` §1.2). Three laws over SwiftUMLBridge's
// `ERScript.sanitizeType`. Each test is named after its law, so the runner can attribute a failure to one cell.
import Foundation
import PropertyBased
import PropertyLawKit
@testable import SanitizerSubject
import Testing

/// The kit's edge-biased `String` expression with the subject's literals, as
/// `RawType.edgeBiasedGeneratorExpression(subjectTokens:)` spells it for the emitted stubs (copied from
/// `fixtures/count-threshold/kill-arm/`).
func edgeBiased(_ literals: [String]) -> Generator<String, some SendableSequenceType> {
    let token = Gen<String?>.element(
        of: ["", " ", "  ", "\n", "\t", "-", "- ", "  -", "- x", "a\n- b", ":", "#", "# ", "/"] as [String]
    ).map { $0! }
    let filler = Gen<Character>.letterOrNumber.string(of: 0 ... 4)
    let subject = Gen<String?>.element(of: literals).map { $0! }
    let short = Gen<Character>.letterOrNumber.string(of: 0 ... 4)
    let embedded = zip(zip(short, subject).map { $0 + $1 }, short).map { $0 + $1 }
    let baseline = Gen.frequency(
        (2.0, Gen<Character>.letterOrNumber.string(of: 0 ... 8)), (1.0, subject), (1.0, embedded)
    )
    return Gen.frequency(
        (3.0, baseline), (1.0, token), (3.0, token.map { $0 + $0 }), (1.0, zip(token, filler).map { $0 + $1 })
    )
}

/// `Safe`, drawn directly (§1.2): non-empty ASCII letters, digits and `_`, length 1–8. Non-empty because of the
/// `isEmpty ? "Unknown" : …` fallback.
func safe() -> Generator<String, some SendableSequenceType> {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
    return Gen<Character?>.element(of: alphabet).map { $0! }.string(of: 1 ... 8)
}

let seed = Seed(stateA: 0x6720_0001, stateB: 0x6720_0002, stateC: 0x6720_0003, stateD: 0x6720_0004)
let literals = ["_", "Unknown"]
let sanitize = ERScript.sanitizeType

/// Idempotence, the law the run scored: `f(f(x)) == f(x)`. The control row.
@Test func idempotence() async {
    let result = await SwiftPropertyBasedBackend().check(
        trials: 100, seed: seed, sample: { rng in edgeBiased(literals).run(using: &rng) },
        property: { text in sanitize(sanitize(text)) == sanitize(text) }
    )
    if case let .failed(_, _, input, _) = result { Issue.record("idempotence failed at \(input.debugDescription)") }
}

/// Law 1, the fixed point: `x ∈ Safe ⟹ f(x) == x`.
@Test func law1() async {
    let result = await SwiftPropertyBasedBackend().check(
        trials: 100, seed: seed, sample: { rng in safe().run(using: &rng) },
        property: { text in sanitize(text) == text }
    )
    if case let .failed(_, _, input, _) = result { Issue.record("law 1 failed at \(input.debugDescription)") }
}

/// Law 2, the output alphabet: every scalar of `f(x)` is alphanumeric or `_`.
@Test func law2() async {
    let result = await SwiftPropertyBasedBackend().check(
        trials: 100, seed: seed, sample: { rng in edgeBiased(literals).run(using: &rng) },
        property: { text in
            sanitize(text).unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "_" }
        }
    )
    if case let .failed(_, _, input, _) = result { Issue.record("law 2 failed at \(input.debugDescription)") }
}

/// Whether this seed's idempotence draws include `""` (§1.4: idempotence kills two mutants only through it).
/// Not a law; it always passes and prints the count, which the runner records.
@Test func emptyDraws() {
    var rng = Xoshiro(seed: (seed.stateA, seed.stateB, seed.stateC, seed.stateD))
    let draws = (0 ..< 100).map { _ in edgeBiased(literals).run(using: &rng) }
    print("EMPTY-DRAWS \(draws.filter(\.isEmpty).count)")
}
