import LeaderboardSort
import PropertyLawKit
import Testing

/// **The functional question: pointed at real types, does the toolchain work?**
///
/// Not a scorecard. The leaderboard fixture tried to score `discover` in isolation and the
/// numbers were noise — a perfect PropertyLawKit with nothing left to infer would have
/// scored it 0% recall, reporting total success as total failure. So this asks whether the
/// pipes connect instead.
///
/// A bug is planted in `ProjectedPlayerScore` for exactly this: a hand-written `==` that
/// compares only `score`, alongside a `hash(into:)` Swift synthesizes from **all** stored
/// properties. That violates `a == b ⟹ a.hashValue == b.hashValue`.
///
/// **Verdict: the system works.** The kit catches it, at `Strict` tier, in 17 trials.
@Suite("Does the kit catch the planted bug?")
struct KitCatchesTheBugTests {

    /// **Narrow** — several names per score, so equal-score / different-name pairs arise.
    /// The projection bug needs a collision to be visible at all.
    private static func narrowProjectedGen() -> Generator<ProjectedPlayerScore, some SendableSequenceType> {
        Gen<Int>.int(in: 0...11).map { ProjectedPlayerScore(name: "P\($0 / 4)", score: $0 % 4) }
    }

    private static func narrowCorrectGen() -> Generator<PlayerScore, some SendableSequenceType> {
        Gen<Int>.int(in: 0...11).map { PlayerScore(name: "P\($0 / 4)", score: $0 % 4) }
    }

    /// **Wide** — the ordinary domain, where a hash is expected to spread.
    private static func wideCorrectGen() -> Generator<PlayerScore, some SendableSequenceType> {
        Gen<Int>.int(in: 0...100_000).map { PlayerScore(name: "P\($0)", score: $0 % 301) }
    }

    // MARK: - 1. The kit passes on the correct type

    @Test("PlayerScore passes the Hashable chain on an ordinary domain")
    func correctTypePasses() async throws {
        let results = try await checkHashablePropertyLaws(
            for: PlayerScore.self,
            using: Self.wideCorrectGen(),
            options: LawCheckOptions(budget: .standard)
        )
        #expect(!results.isEmpty, "the suite must actually run laws")
        let failed = results.filter { $0.outcome != .passed }
        #expect(failed.isEmpty, Comment(rawValue: "failures: \(failed.map(\.protocolLaw))"))
    }

    // MARK: - 2. The kit catches the planted bug

    /// **The load-bearing test.** If this stops throwing, the toolchain is not doing its job.
    ///
    /// `EnforcementMode.default` throws on `Strict`-tier violations, and
    /// `Hashable.equalityConsistency` is Strict — so the *shape* of a caught bug here is a
    /// thrown `PropertyLawViolation`, not a `.failed` result to inspect.
    @Test("ProjectedPlayerScore is REJECTED — the planted bug is caught")
    func brokenTypeIsCaught() async throws {
        // The kit records a swift-testing Issue itself on a Strict violation, so a bare
        // do/catch still fails the enclosing test. `.intentionalViolation` is the kit's own
        // way to say "this violation is the documented design": the outcome becomes
        // `.expectedViolation` instead, carrying the counterexample. Asserting on THAT is
        // how a fixture proves detection without the detection failing it.
        let options = LawCheckOptions(
            budget: .standard,
            suppressions: [
                .intentionalViolation(
                    LawIdentifier(protocolName: "Hashable", lawName: "equalityConsistency"),
                    reason: "planted: `==` projects to `score`, `hash(into:)` is synthesized "
                        + "from all stored properties. This fixture exists to confirm the kit "
                        + "catches it."
                ),
                // The narrow generator is degenerate for the distribution heuristic — see
                // the tension test below. Skipped here so this test asserts one thing.
                .skip(
                    LawIdentifier(protocolName: "Hashable", lawName: "distribution"),
                    reason: "a 12-value domain is degenerate by construction; the collision "
                        + "density is what makes the planted bug reachable at all."
                )
            ]
        )
        let results = try await checkHashablePropertyLaws(
            for: ProjectedPlayerScore.self,
            using: Self.narrowProjectedGen(),
            options: options
        )
        let expected = results.filter {
            if case .expectedViolation = $0.outcome { return true }
            return false
        }
        #expect(
            expected.count == 1,
            Comment(rawValue: "the kit must detect the planted bug — outcomes: "
                + "\(results.map { "\($0.protocolLaw)=\($0.outcome)" })")
        )
        #expect(expected.first?.protocolLaw.contains("equalityConsistency") == true)
        #expect(expected.first?.tier == .strict, "and it must be a Strict-tier law")
    }

    // MARK: - 3. …and the Equatable laws pass on the same broken type

    /// The contrast that makes 2 meaningful. A projection is a legitimate equivalence
    /// relation, so reflexivity / symmetry / transitivity all hold on a type that is wrong —
    /// `fixtures/equatable-signal` measured three real swift-collections bugs passing 4 of 4.
    ///
    /// **The kit's verdict on this type is split, and the split is the finding**: the
    /// Equatable suite says fine, the Hashable suite says broken, and only one of them looks
    /// at the field the `==` forgot.
    @Test("...while the Equatable laws pass on the same broken type")
    func equatableLawsPassOnTheBrokenType() async throws {
        let results = try await checkEquatablePropertyLaws(
            for: ProjectedPlayerScore.self,
            using: Self.narrowProjectedGen(),
            options: LawCheckOptions(budget: .standard)
        )
        #expect(!results.isEmpty)
        let failed = results.filter { $0.outcome != .passed }
        #expect(
            failed.isEmpty,
            Comment(rawValue: "a projection IS an equivalence relation — these should pass: "
                + "\(failed.map(\.protocolLaw))")
        )
    }

    // MARK: - 4. The tension the first run exposed

    /// **The generator that exposes one law's bug violates another law's assumptions.**
    ///
    /// The first version of this suite used the narrow generator everywhere, and the
    /// *correct* type failed — on `Hashable.distribution`, a **Heuristic**-tier law, because
    /// 12 distinct values over 1000 trials is a degenerate hash distribution.
    ///
    /// That is not a nuisance to tune away. The projection bug needs collisions to be
    /// visible; the distribution law needs their absence. **One generator cannot serve both
    /// laws in the same suite**, and `checkHashablePropertyLaws` runs them together.
    ///
    /// Tier is what makes this survivable: `EnforcementMode.default` throws only on
    /// `Strict`, so the heuristic complaint is reported without failing the run. A reader who
    /// narrows a generator to hunt a collision bug should expect the distribution law to
    /// grumble and should not widen the generator to silence it — that would hide the bug
    /// they narrowed it to find.
    @Test("the narrow generator trips the heuristic distribution law on the CORRECT type")
    func narrowGeneratorTripsDistributionOnACorrectType() async throws {
        let options = LawCheckOptions(
            budget: .standard,
            suppressions: [
                .intentionalViolation(
                    LawIdentifier(protocolName: "Hashable", lawName: "distribution"),
                    reason: "the point of this test: a correct type fails the distribution "
                        + "heuristic purely because the generator was narrowed to hunt a "
                        + "collision bug."
                )
            ]
        )
        let results = try await checkHashablePropertyLaws(
            for: PlayerScore.self,
            using: Self.narrowCorrectGen(),
            options: options
        )
        let flagged = results.filter {
            if case .expectedViolation = $0.outcome { return true }
            return false
        }
        #expect(!flagged.isEmpty, "a 12-value domain is a degenerate hash distribution")
        #expect(
            flagged.allSatisfy { $0.tier != .strict },
            Comment(rawValue: "…and it must be non-Strict, or a CORRECT type would be "
                + "rejected outright: \(flagged.map { "\($0.protocolLaw) [\($0.tier)]" })")
        )
    }
}
