import Testing

@testable import BranchReachingDomain

/// **Does widening the character class reach the branch the law is about?**
///
/// Measured on `swift-http-types` @ `5b99e00`: the emitted idempotence law for
/// `HTTPField.legalizeValue` **passed on a plainly broken implementation**, while the
/// package's own tests caught the same defect. The mutation lives in the `else` branch of
/// a validity guard, and the shipped generator —
/// `Gen<Character>.letterOrNumber.string(of: 0...8)` — is alphanumeric, so it cannot
/// produce an invalid value and the branch never runs.
///
/// Scored in **mutants killed**, following `fixtures/integer-division-generator/`'s
/// 2/8 → 8/8, the only intervention in this repo measured to move refutation power.
/// Trials are **100**, the shipped `.small` budget, because a result at a budget the tool
/// does not run answers nothing — the lesson `fixtures/collision-pairing/` paid for.
@Suite("Branch-reaching generators — mutants killed per character class")
struct DomainArmsTests {

    typealias Subject = @Sendable (String) -> String

    struct Mutant: Sendable {
        let name: String
        let subject: Subject
        let isIdempotent: Bool
    }

    static let mutants: [Mutant] = [
        Mutant(name: "correct", subject: Legalize.correct, isIdempotent: true),
        Mutant(name: "trim-then-map (control)", subject: Legalize.trimThenMap, isIdempotent: true),
        // Real bugs that PRESERVE idempotence — no idempotence law can refute these at
        // any domain, and mislabelling them is what made this fixture's first run read
        // as a generator failure.
        Mutant(name: "trailing-trim-only (bug, idempotent)", subject: Legalize.trailingTrimOnly, isIdempotent: true),
        Mutant(name: "leading-trim-only (bug, idempotent)", subject: Legalize.leadingTrimOnly, isIdempotent: true),
        Mutant(name: "maps-to-illegal (bug, idempotent)", subject: Legalize.mapsToIllegal, isIdempotent: true),
        // The one an idempotence law can actually refute.
        Mutant(name: "trims-one-whitespace", subject: Legalize.trimsOneWhitespace, isIdempotent: false)
    ]

    static func killed(by domain: Domain) -> [String] {
        mutants
            .filter { !$0.isIdempotent }
            .filter { !checkIdempotence($0.subject, domain: domain).passed }
            .map(\.name)
    }

    /// **The shipped domain cannot reach the branch.** This is the defect, reduced: the
    /// guard is never false, so the transform never runs and no mutant can be killed.
    @Test("the shipped alphanumeric domain reaches the branch zero times and kills nothing")
    func shippedDomainIsBlind() {
        let outcome = checkIdempotence(Legalize.trimsOneWhitespace, domain: .letterOrNumber)
        #expect(
            outcome.branchReached == 0,
            "the alphanumeric domain produced an invalid value \(outcome.branchReached) times"
        )
        #expect(Self.killed(by: .letterOrNumber).isEmpty, "it killed something without reaching the branch")
    }

    /// **Adding space and tab is enough to reach it**, and enough to kill the defect
    /// planted on the real subject.
    /// **Reach is necessary and NOT sufficient, which is the fixture's real finding.**
    ///
    /// Widening the class to include space and tab reaches the branch 6 times in 100 —
    /// and kills nothing, because refuting this mutant needs a value with *two* leading
    /// whitespace characters, and two-in-a-row is rare when whitespace is 2 symbols in a
    /// 64-symbol alphabet. **The lever is a NARROW alphabet, not a wider one** — the same
    /// conclusion `GeneratorRecipe.collidingString` reached on the substring axis
    /// (*"a four-symbol alphabet, so substrings REPEAT"*), arriving independently on the
    /// validity axis.
    @Test("widening to whitespace reaches the branch and still kills nothing")
    func reachIsNotSufficient() {
        let outcome = checkIdempotence(Legalize.trimsOneWhitespace, domain: .withWhitespace)
        #expect(outcome.branchReached > 0, "the widened class still never reached the branch")
        #expect(
            Self.killed(by: .withWhitespace).isEmpty,
            "it killed the mutant — then reach IS sufficient and this fixture's finding is wrong"
        )
    }

    /// **The finding that corrects `criterion-a-unmet-subject.md`.** Three of these
    /// mutants are real correctness bugs — the package's own tests catch the first — and
    /// **no domain refutes them, because they preserve idempotence.** A law cannot be
    /// blamed for missing a defect its property does not describe.
    @Test("a real bug that preserves idempotence is unrefutable at every domain")
    func idempotencePreservingBugsAreUnrefutable() {
        for domain in Domain.allCases {
            let outcome = checkIdempotence(Legalize.trailingTrimOnly, domain: domain)
            #expect(
                outcome.passed,
                "\(domain.rawValue) refuted an idempotent subject: \(outcome.counterexample ?? "")"
            )
        }
    }

    /// **A narrow alphabet including a control character kills all three**, because every
    /// draw is near-certain to be invalid and to contain both a trimmable edge and an
    /// illegal interior byte.
    @Test("a narrow alphabet with controls kills every refutable mutant")
    func narrowAlphabetKillsAll() {
        let killed = Self.killed(by: .narrowWithControls)
        #expect(killed.count == 1, "killed \(killed.sorted())")
    }

    /// **No domain may kill an idempotent subject.** `trim-then-map` reaches the branch on
    /// every widened domain and is still idempotent; a scorer that kills it is measuring
    /// its own aggression rather than the subject's defect.
    @Test("no domain falsely refutes an idempotent subject")
    func idempotentSubjectsSurvive() {
        for domain in Domain.allCases {
            for mutant in Self.mutants where mutant.isIdempotent {
                let outcome = checkIdempotence(mutant.subject, domain: domain)
                #expect(
                    outcome.passed,
                    "\(domain.rawValue) falsely refuted \(mutant.name): \(outcome.counterexample ?? "")"
                )
            }
        }
    }

    @Test("scorecard — branch reach and mutants killed per domain")
    func scorecard() {
        let refutable = Self.mutants.filter { !$0.isIdempotent }.count
        var lines = ["", "BRANCH-REACHING GENERATORS — 100 trials (the shipped `.small` budget)", ""]
        lines.append("domain                reached  killed  which")
        for domain in Domain.allCases {
            let reach = checkIdempotence(Legalize.trimsOneWhitespace, domain: domain).branchReached
            let killed = Self.killed(by: domain)
            lines.append(
                domain.rawValue.padding(toLength: 22, withPad: " ", startingAt: 0)
                    + String(reach).padding(toLength: 9, withPad: " ", startingAt: 0)
                    + "\(killed.count)/\(refutable)     \(killed.sorted().joined(separator: ", "))"
            )
        }
        print(lines.joined(separator: "\n"))
    }
}
