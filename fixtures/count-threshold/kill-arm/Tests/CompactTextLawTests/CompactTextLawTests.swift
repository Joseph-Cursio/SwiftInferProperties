// #670's kill arm (`docs/plans/count-threshold-boundary-census-scope.md` §1.2). Three laws over `compactText`
// at two revisions. Each test is named `<law>_<revision>`, so the runner can attribute a failure to one cell.
//
// Law 1 and Law 2 restate the body, so on the original they hold by construction. What they catch is an edit
// to the threshold, and that is the measurement: which law notices which of the three `:200` mutants.
import CompactTextSubject
import PropertyBased
import PropertyLawKit
import Testing

/// One revision's subject and the counted expression its body tests, with the `let`s inlined.
struct Revision: Sendable {
    let name: String
    let subject: @Sendable (String) -> String
    let counted: @Sendable (String) -> String
    /// The literals `SubjectLiterals.harvest` keeps for the body, in source order and deduplicated.
    let literals: [String]
}

let e36da59 = Revision(
    name: "e36da59",
    subject: CompactTextE36da59.compactText,
    counted: { text in
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    },
    literals: ["\n", " ", "…"]
)

let r9ad7631 = Revision(
    name: "9ad7631",
    subject: CompactText9ad7631.compactText,
    counted: { text in
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    },
    literals: [" ", "…"]
)

/// The boundary walk: 20 letters-and-digits strings at each of 79, 80 and 81 Characters. On this input the
/// collapse is the identity, so the drawn length is the counted length.
func walk() -> [String] {
    var rng = Xoshiro(seed: (0x670A, 0x670B, 0x670C, 0x670D))
    return [79, 80, 81].flatMap { length in
        (0 ..< 20).map { _ in Gen<Character>.letterOrNumber.string(of: length ... length).run(using: &rng) }
    }
}

/// The kit's edge-biased `String` expression with the subject's literals, as
/// `RawType.edgeBiasedGeneratorExpression(subjectTokens:)` spells it for the emitted stubs.
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

let seed = Seed(stateA: 0x6700_0001, stateB: 0x6700_0002, stateC: 0x6700_0003, stateD: 0x6700_0004)

/// Law 1, on the side the boundary sits on: `e(x).count <= 80 ⟹ f(x) == e(x)`, over the walk.
func law1(_ revision: Revision) {
    for text in walk() where revision.counted(text).count <= 80 {
        let result = revision.subject(text)
        #expect(result == revision.counted(text), "Law 1 failed at length \(text.count): \(result.count) back")
    }
}

/// Law 2, the cap: `f(x).count <= 80`, over the walk and 100 sampled draws.
func law2(_ revision: Revision) async {
    for text in walk() {
        #expect(revision.subject(text).count <= 80, "Law 2 failed at length \(text.count)")
    }
    let result = await SwiftPropertyBasedBackend().check(
        trials: 100,
        seed: seed,
        sample: { rng in edgeBiased(revision.literals).run(using: &rng) },
        property: { text in revision.subject(text).count <= 80 }
    )
    if case let .failed(_, _, input, _) = result { Issue.record("Law 2 failed at \(input.debugDescription)") }
}

/// The idempotence law the tool emits: `f(f(x)) == f(x)`, 100 trials of the edge-biased expression.
func idempotence(_ revision: Revision) async {
    let result = await SwiftPropertyBasedBackend().check(
        trials: 100,
        seed: seed,
        sample: { rng in edgeBiased(revision.literals).run(using: &rng) },
        property: { text in revision.subject(revision.subject(text)) == revision.subject(text) }
    )
    if case let .failed(_, _, input, _) = result { Issue.record("idempotence failed at \(input.debugDescription)") }
}

@Test func law1_e36da59() { law1(e36da59) }
@Test func law1_9ad7631() { law1(r9ad7631) }
@Test func law2_e36da59() async { await law2(e36da59) }
@Test func law2_9ad7631() async { await law2(r9ad7631) }
@Test func idempotence_e36da59() async { await idempotence(e36da59) }
@Test func idempotence_9ad7631() async { await idempotence(r9ad7631) }
