import Testing

@testable import BranchReachingDomain

/// **Which law family actually refutes a normaliser's bugs?**
///
/// `DomainArmsTests` established that three real correctness bugs in a legalise-shaped
/// function are **unrefutable by idempotence at any generator domain**, because mapping is
/// a fixpoint and trimming converges. That is a fact about the *law*, not the generator.
///
/// So this asks the next question: given the same three bugs, which of the common law
/// shapes refutes them? Scored in mutants killed, at the **narrow** domain throughout —
/// `DomainArmsTests` already showed the shipped alphanumeric domain reaches the branch
/// zero times, and a law comparison run there would score every law at zero and say
/// nothing about the laws.
@Suite("Law comparison — which property refutes a normaliser's bugs?")
struct LawComparisonTests {

    typealias Subject = @Sendable (String) -> String

    struct Law: Sendable {
        let name: String
        /// True when the subject SATISFIES the law on this input.
        let holds: @Sendable (Subject, String) -> Bool
    }

    /// The law shapes, in the vocabulary this project uses.
    static let laws: [Law] = [
        // f(f(x)) == f(x)
        Law(name: "idempotence") { f, x in f(f(x)) == f(x) },
        // The DEFINING property of a normaliser: the output is normal.
        Law(name: "postcondition: isValid(f(x))") { f, x in isValidValue(f(x)) },
        // Identity element: an already-normal value is unchanged.
        Law(name: "identity-on-normal") { f, x in isValidValue(x) ? f(x) == x : true },
        // Metamorphic: adding removable noise does not change the normal form.
        Law(name: "metamorphic: f(\" \"+x) == f(x)") { f, x in f(" " + x) == f(x) },
        Law(name: "metamorphic: f(x+\" \") == f(x)") { f, x in f(x + " ") == f(x) },
        // Oracle: agree with an independently written correct implementation.
        Law(name: "oracle vs trim-then-map") { f, x in f(x) == Legalize.trimThenMap(x) }
    ]

    struct Mutant: Sendable {
        let name: String
        let subject: Subject
        /// Is this a genuine correctness defect?
        let isBug: Bool
    }

    static let mutants: [Mutant] = [
        Mutant(name: "correct", subject: Legalize.correct, isBug: false),
        Mutant(name: "trailing-trim-only", subject: Legalize.trailingTrimOnly, isBug: true),
        Mutant(name: "leading-trim-only", subject: Legalize.leadingTrimOnly, isBug: true),
        Mutant(name: "maps-to-illegal", subject: Legalize.mapsToIllegal, isBug: true),
        Mutant(name: "trims-one-whitespace", subject: Legalize.trimsOneWhitespace, isBug: true)
    ]

    /// 100 trials, the shipped `.small` budget, narrow domain.
    static func refutes(_ law: Law, _ subject: Subject, seed: UInt64 = 0x5EED_1234) -> Bool {
        var generator = SeededGenerator(seed: seed)
        for _ in 0 ..< 100 where !law.holds(subject, Domain.narrowWithControls.sample(&generator)) {
            return true
        }
        return false
    }

    static func killed(by law: Law) -> [String] {
        mutants.filter(\.isBug).filter { refutes(law, $0.subject) }.map(\.name)
    }

    /// **No law may refute the correct implementation.** Without this a law that returns
    /// false constantly would score 4/4 and look like the answer.
    @Test("no law refutes the correct implementation")
    func correctSurvivesEveryLaw() {
        for law in Self.laws {
            #expect(
                !Self.refutes(law, Legalize.correct),
                "\(law.name) refuted the correct implementation — it is not a law of this subject"
            )
        }
    }

    /// **Idempotence is the weakest of the six**, and this pins the gap that
    /// `criterion-a-unmet-subject.md` §3.1 corrects.
    @Test("idempotence refutes only the non-idempotent bug")
    func idempotenceIsWeak() {
        let killed = Self.killed(by: Self.laws[0])
        #expect(killed == ["trims-one-whitespace"], "killed \(killed.sorted())")
    }

    /// **The postcondition is the defining property, and it refutes all four.**
    @Test("the postcondition refutes every bug")
    func postconditionIsStrongest() {
        let killed = Self.killed(by: Self.laws[1])
        let bugs = Self.mutants.filter(\.isBug).count
        #expect(killed.count == bugs, "killed \(killed.count) of \(bugs): \(killed.sorted())")
    }

    @Test("scorecard — mutants killed per law")
    func scorecard() {
        let bugs = Self.mutants.filter(\.isBug).count
        var lines = ["", "LAW COMPARISON — normaliser bugs killed (narrow domain, 100 trials)", ""]
        lines.append("law                                 killed  which")
        for law in Self.laws {
            let killed = Self.killed(by: law)
            lines.append(
                law.name.padding(toLength: 36, withPad: " ", startingAt: 0)
                    + "\(killed.count)/\(bugs)     \(killed.sorted().joined(separator: ", "))"
            )
        }
        print(lines.joined(separator: "\n"))
    }
}
