import Testing

@testable import CollisionPairingDomain

/// **Does deriving the second operand from the first buy refutations that independent
/// draws cannot — at the trial budget the tool actually ships?**
///
/// Scored in **mutants killed**, following `fixtures/integer-division-generator/`, the
/// only intervention in this repo measured to improve refutation power (2/8 → 8/8). A
/// suggestion count cannot answer this: the suggestion is emitted either way, and the
/// question is whether the emitted law can *fail*.
///
/// ## The first version of this fixture had its premise falsified, and the fix is the finding
///
/// It asserted that independent draws never make two dictionary operands share a key, so
/// a tie-break mutant survives. **Measured, independent draws killed 3 of 3.** Keys drawn
/// from a *finite* range do collide: at ~2.5 keys per side against 10,000 possible keys
/// the per-trial collision probability is ~6e-4, so 20,000 trials expect a dozen hits.
/// The blind spot is not "this domain cannot collide" — it is **"this domain cannot
/// collide often enough to be found inside the budget the emitter uses"**.
///
/// `RoundTripStubEmitter.TrialBudget` is **100** (`.small`, the V1.42 default) or
/// **1,000** (`.standard`). Twenty thousand is not a budget this tool ever runs, so the
/// original arm scored a configuration that does not ship. The arms below are the
/// shipped numbers, with 20,000 kept only as the contrast that shows where the blind
/// spot closes.
@Suite("Collision pairing — mutants killed per pairing, per shipped trial budget")
struct PairingArmsTests {

    typealias Subject = @Sendable ([Int: Int], [Int: Int]) -> [Int: Int]

    struct Mutant: Sendable {
        let name: String
        let subject: Subject
        let isCommutative: Bool
    }

    static let mutants: [Mutant] = [
        Mutant(name: "correct (max)", subject: Merge.correct, isCommutative: true),
        Mutant(name: "min-on-collision (control)", subject: Merge.minOnCollision, isCommutative: true),
        Mutant(name: "last-write-wins", subject: Merge.lastWriteWins, isCommutative: false),
        Mutant(name: "first-write-wins", subject: Merge.firstWriteWins, isCommutative: false),
        Mutant(name: "drops-left-only", subject: Merge.dropsLeftOnly, isCommutative: false)
    ]

    /// `.small` and `.standard` are the emitter's two budgets. 20,000 is not a budget the
    /// tool offers and is present only to locate the crossover.
    static let budgets: [(label: String, trials: Int, isShipped: Bool)] = [
        ("small (100)", 100, true),
        ("standard (1,000)", 1_000, true),
        ("exhaustive (20,000)", 20_000, false)
    ]

    static func killed(by pairing: Pairing, trials: Int, keySpace: KeySpace = .narrow) -> [String] {
        mutants
            .filter { !$0.isCommutative }
            .filter {
                !checkCommutativity($0.subject, pairing: pairing, keySpace: keySpace, trials: trials).passed
            }
            .map(\.name)
    }

    /// **On a NARROW key space the gap is a budget effect, and closes without pairing.**
    ///
    /// This is the arm that refuted the fixture's first premise. At `.small` (100)
    /// independent draws kill 1 of 3; at `.standard` (1,000) they kill 3 of 3. So for a
    /// domain this size, **raising the trial budget is a cheaper fix than a pairing
    /// pass**, and this arm exists to stop anyone claiming otherwise.
    @Test("on a narrow key space, a larger budget closes the gap without pairing")
    func narrowSpaceGapIsABudgetEffect() {
        let atSmall = Self.killed(by: .independent, trials: 100, keySpace: .narrow)
        let atStandard = Self.killed(by: .independent, trials: 1_000, keySpace: .narrow)
        #expect(!atSmall.contains("last-write-wins"), "100 trials found it; re-check the key space")
        #expect(
            atStandard.contains("last-write-wins") && atStandard.contains("first-write-wins"),
            "1,000 trials did not close it — then the narrow-space claim is wrong"
        )
    }

    /// **On a WIDE key space no budget closes it, and pairing is the only lever.**
    ///
    /// A billion keys is the analogue of `CommutativityStubEmitter`'s real default,
    /// which draws `Complex<Double>` from ±1,000,000. Independent operands never share a
    /// key at any budget the tool could run, so the tie-break is unreachable by
    /// increasing trials — the case that justifies building the pairing at all.
    @Test("on a wide key space, no shipped budget reaches the tie-break")
    func wideSpaceIsUnreachableByBudget() {
        for trials in [100, 1_000, 20_000] {
            let killed = Self.killed(by: .independent, trials: trials, keySpace: .wide)
            #expect(
                !killed.contains("last-write-wins"),
                "\(trials) independent trials collided on a billion-key space"
            )
            #expect(!killed.contains("first-write-wins"), "\(trials) trials collided on a wide space")
        }
        let paired = Self.killed(by: .overlapping, trials: 100, keySpace: .wide)
        #expect(
            paired.contains("last-write-wins") && paired.contains("first-write-wins"),
            "pairing failed on the wide space, which is the only case that justifies it"
        )
    }

    /// **The lever works inside the budget.** Overlapping operands force the tie-break on
    /// every trial, so 100 is enough.
    @Test("overlapping draws kill the tie-break mutants at the smallest shipped budget")
    func overlappingKillsWithinBudget() {
        let killed = Self.killed(by: .overlapping, trials: 100)
        #expect(killed.contains("last-write-wins"), "overlapping did not reach the tie-break")
        #expect(killed.contains("first-write-wins"))
    }

    /// **`identical` kills nothing here, and that is not a defect.** `f(a, a) == f(a, a)`
    /// is a tautology for any deterministic subject. Pinned so nobody adds the diagonal
    /// to a commutativity pass expecting a gain; it earns its place on other laws.
    @Test("the diagonal is tautological on commutativity")
    func identicalIsTautological() {
        #expect(
            Self.killed(by: .identical, trials: 1_000).isEmpty,
            "a kill here means the subject is nondeterministic, not that the diagonal works"
        )
    }

    /// **`permuted` cannot kill what has no left-exclusive keys.** It reuses the first
    /// operand's key set exactly, so `drops-left-only` is unreachable by construction —
    /// which is the concrete form of *paired draws are additive, never a replacement*.
    @Test("permuted misses the mutant that independent draws catch")
    func pairingIsAdditiveNotBetter() {
        let permuted = Self.killed(by: .permuted, trials: 1_000)
        let independent = Self.killed(by: .independent, trials: 1_000)
        #expect(
            !permuted.contains("drops-left-only"),
            "permuted reuses the left key set, so a left-exclusive-key mutant cannot show"
        )
        #expect(
            independent.contains("drops-left-only"),
            "if independent misses it too, nothing here argues for keeping the default pass"
        )
    }

    /// **No pairing may kill a commutative subject.** `min-on-collision` is the control:
    /// it collides on every shared key and is still commutative, so a scorer that kills
    /// it is measuring its own aggression.
    @Test("no pairing falsely refutes a commutative subject")
    func commutativeSubjectsSurvive() {
        for pairing in Pairing.allCases {
            for mutant in Self.mutants where mutant.isCommutative {
                let outcome = checkCommutativity(mutant.subject, pairing: pairing, trials: 1_000)
                #expect(
                    outcome.passed,
                    "\(pairing.rawValue) falsely refuted \(mutant.name): \(outcome.counterexample ?? "")"
                )
            }
        }
    }

    @Test("scorecard — mutants killed per pairing per budget")
    func scorecard() {
        let refutable = Self.mutants.filter { !$0.isCommutative }.count
        var lines = ["", "COLLISION PAIRING — MUTANTS KILLED", "", "refutable mutants: \(refutable)"]
        for keySpace in KeySpace.allCases {
            lines.append("")
            lines.append("=== key space: \(keySpace.rawValue) (0 ..< \(keySpace.upperBound)) ===")
            for budget in Self.budgets {
                lines.append("")
                lines.append("\(budget.label)\(budget.isShipped ? "" : "   [NOT a budget the tool runs]")")
                for pairing in Pairing.allCases {
                    let killed = Self.killed(by: pairing, trials: budget.trials, keySpace: keySpace)
                    lines.append("  \(pairing.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0))"
                        + "\(killed.count)/\(refutable)  \(killed.sorted().joined(separator: ", "))")
                }
            }
        }
        print(lines.joined(separator: "\n"))
    }
}
