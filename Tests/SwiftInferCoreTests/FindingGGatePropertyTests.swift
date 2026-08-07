import Foundation
import PropertyLawKit
import SwiftInferCore
import Testing

// Self-dogfood road test (`docs/measurements/roadtest-self-dogfood.md`) — the two precision
// decisions `CLAUDE.md` lists under "follow rather than re-litigate," executed
// rather than asserted.
//
// The Finding-G gate is the tool's sharpest published claim about its own
// output: cardinality and biconditional detect a *representable illegal state*,
// a shape that holds as a runtime property only 33–50% of the time, so those
// two families are pinned at `.possible` and must never promote — **except**
// when measured execution establishes a `bothPass` at full action-space
// coverage (cycle 135), which is sound per-candidate proof and overrules the
// pin. A partial bothPass does not overrule, because the failure mode lives in
// exactly the action types partial exploration skips.
//
// The source calls `tier(forScore:)` the "single source of truth … so the gate
// can't be bypassed on one path and not the other." That sentence is a law with
// no test behind it. What follows is the test: the gate stated over the full
// cross product of family × score, and the fold stated over family × outcome ×
// coverage, so neither the pin nor its one carve-out can be widened by accident.
@Suite("Road test — Finding-G gate and the verify-evidence fold")
struct FindingGGatePropertyTests {

    // MARK: - Fixtures

    /// The two families carrying a `swiftProjectLintDeferral`, derived from the
    /// property itself rather than hard-coded. A family added to the deferral
    /// list later is picked up here automatically — hard-coding
    /// `[.cardinality, .biconditional]` would silently stop covering it.
    private static let gatedFamilies = InteractionInvariantFamily.allCases
        .filter { $0.swiftProjectLintDeferral != nil }

    private static let ungatedFamilies = InteractionInvariantFamily.allCases
        .filter { $0.swiftProjectLintDeferral == nil }

    private static let scoreSweep = Array(-10...130)

    private static func suggestion(
        family: InteractionInvariantFamily,
        score: Int,
        tier: Tier? = nil
    ) -> InteractionInvariantSuggestion {
        InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: "\(family.rawValue)::Feature.reduce::p"),
            family: family,
            reducerQualifiedName: "Feature.reduce",
            reducerLocation: "Feature.swift:1",
            stateTypeName: "State",
            actionTypeName: "Action",
            predicate: "p",
            score: score,
            tier: tier ?? family.tier(forScore: score),
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: Date(timeIntervalSince1970: 1_000_000)
        )
    }

    private static func evidence(
        for suggestion: InteractionInvariantSuggestion,
        outcome: VerifyEvidenceOutcome,
        excludedActionCount: Int?
    ) -> [String: VerifyEvidence] {
        [
            suggestion.identity.normalized: VerifyEvidence(
                identityHash: suggestion.identity.normalized,
                template: suggestion.family.rawValue,
                outcome: outcome,
                detail: nil,
                capturedAt: Date(timeIntervalSince1970: 1_000_000),
                swiftInferVersion: "test",
                excludedActionCount: excludedActionCount
            )
        ]
    }

    // MARK: - The gate itself

    /// "A family carrying a `swiftProjectLintDeferral` is **clamped to
    /// `.possible` regardless of score**." Swept over the whole threshold
    /// domain, exhaustively — a score arm that leaked past the clamp at one
    /// value would be exactly the bug this sentence exists to prevent, and
    /// sampling would find it four runs in five at best.
    @Test("a gated family is pinned to .possible at every score")
    func gatedFamiliesArePinnedAtEveryScore() {
        #expect(!Self.gatedFamilies.isEmpty, "the gate has no subjects — the fixture is wrong")
        for family in Self.gatedFamilies {
            for score in Self.scoreSweep {
                #expect(family.tier(forScore: score) == .possible, "\(family) leaked at \(score)")
            }
        }
    }

    /// The other half, and the one that keeps the gate from quietly becoming a
    /// global clamp: an ungated family must be *transparent* — its tier is
    /// exactly `Tier(score:)`, with no adjustment of any kind.
    @Test("an ungated family is transparent to Tier(score:)")
    func ungatedFamiliesAreTransparent() {
        #expect(!Self.ungatedFamilies.isEmpty)
        for family in Self.ungatedFamilies {
            for score in Self.scoreSweep {
                #expect(family.tier(forScore: score) == Tier(score: score), "\(family) at \(score)")
            }
        }
    }

    /// Exactly the two documented families are gated. Pinned as a
    /// characterization so that adding a third — which may well be right — is a
    /// deliberate edit to a test that names the precision decision, rather than
    /// a silent widening of the pin.
    @Test("exactly cardinality and biconditional carry a deferral")
    func exactlyTwoFamiliesAreGated() {
        #expect(Set(Self.gatedFamilies) == [.cardinality, .biconditional])
        #expect(InteractionInvariantFamily.cardinality.swiftProjectLintDeferral
            == "mutually-exclusive-presentation-state")
        #expect(InteractionInvariantFamily.biconditional.swiftProjectLintDeferral
            == "flag-optional-pair-state")
    }

    // MARK: - The fold

    /// "A suggestion with no evidence passes through unchanged (identical
    /// value, so callers can rely on `==`)." The docstring promises value
    /// identity, not merely equivalent grading — so the law is `==` on the whole
    /// suggestion, which also catches a fold that appended an empty
    /// explainability line or re-stamped `firstSeenAt`.
    @Test("no evidence — the fold is the identity function")
    func noEvidenceIsIdentity() {
        for family in InteractionInvariantFamily.allCases {
            for score in [0, 30, 40, 80] {
                let input = [Self.suggestion(family: family, score: score)]
                #expect(InteractionVerifyEvidenceScoring.applied(to: input, evidenceByIdentity: [:]) == input)
            }
        }
    }

    /// "Pure and order-preserving." Length and per-position identity are what
    /// the render path relies on downstream, and neither is guaranteed by the
    /// `map` alone once a future contributor reaches for `filter` to drop
    /// suppressed picks inside the fold instead of after it.
    @Test("the fold preserves length and order")
    func foldPreservesLengthAndOrder() {
        let inputs = InteractionInvariantFamily.allCases.map { Self.suggestion(family: $0, score: 30) }
        let folded = InteractionVerifyEvidenceScoring.applied(
            to: inputs,
            evidenceByIdentity: Self.evidence(for: inputs[0], outcome: .measuredBothPass, excludedActionCount: 0)
        )
        #expect(folded.count == inputs.count)
        #expect(folded.map(\.identity.normalized) == inputs.map(\.identity.normalized))
        #expect(folded.map(\.family) == inputs.map(\.family))
    }

    /// "`.measuredDefaultFails` → collapse to `.suppressed`." Universally: an
    /// executed counterexample outranks every family, every score, and the
    /// Finding-G gate itself. This is the veto direction, and it is the one that
    /// must have no exceptions — a disproven property is wrong, not merely
    /// low-confidence.
    @Test("defaultFails suppresses every family at every score")
    func defaultFailsAlwaysSuppresses() {
        for family in InteractionInvariantFamily.allCases {
            for score in [0, 20, 40, 75, 120] {
                let pick = Self.suggestion(family: family, score: score)
                let folded = InteractionVerifyEvidenceScoring.applied(
                    to: [pick],
                    evidenceByIdentity: Self.evidence(
                        for: pick,
                        outcome: .measuredDefaultFails,
                        excludedActionCount: 0
                    )
                )
                #expect(folded[0].tier == .suppressed, "\(family) at \(score) escaped the veto")
                #expect(folded[0].whyMightBeWrong.count == pick.whyMightBeWrong.count + 1)
            }
        }
    }

    /// The non-verdicts are score- and tier-neutral pass-throughs. Worth stating
    /// because three of the five `VerifyEvidenceOutcome` cases land here, and
    /// "not a verdict" is easy to erode into "a weak verdict."
    @Test("edge-case, error, and coverage-pending outcomes change nothing")
    func nonVerdictOutcomesAreNeutral() {
        let neutral: [VerifyEvidenceOutcome] = [
            .measuredEdgeCaseAdvisory, .measuredError, .architecturalCoveragePending
        ]
        for family in InteractionInvariantFamily.allCases {
            for outcome in neutral {
                let pick = Self.suggestion(family: family, score: 40)
                let folded = InteractionVerifyEvidenceScoring.applied(
                    to: [pick],
                    evidenceByIdentity: Self.evidence(for: pick, outcome: outcome, excludedActionCount: 0)
                )
                #expect(folded == [pick], "\(outcome) moved a \(family) pick")
            }
        }
    }

    // MARK: - The carve-out, stated over its full domain

    /// **The cycle-135 decision, as a law: a gated family promotes on a measured
    /// `bothPass` if and only if coverage is full.**
    ///
    /// This is the sharpest test in the road test, because both directions are
    /// load-bearing precision decisions and they point opposite ways. Overrule
    /// too eagerly (accept a partial bothPass) and a false positive reaches the
    /// default surface through the one gate built to stop it. Overrule too
    /// timidly (never) and full-coverage measured proof is thrown away. The
    /// `nil` arm is the third case and it is the one a reader gets wrong:
    /// legacy evidence predating cycle 136 recorded no coverage, and it must be
    /// treated as *partial*, not as "no exclusions."
    @Test("a gated family promotes on bothPass iff coverage is full")
    func gatedPromotionRequiresFullCoverage() {
        let coverages: [Int?] = [0, 1, 3, nil]
        for family in Self.gatedFamilies {
            for coverage in coverages {
                let pick = Self.suggestion(family: family, score: 30)
                #expect(pick.tier == .possible, "fixture precondition")
                let folded = InteractionVerifyEvidenceScoring.applied(
                    to: [pick],
                    evidenceByIdentity: Self.evidence(
                        for: pick,
                        outcome: .measuredBothPass,
                        excludedActionCount: coverage
                    )
                )[0]

                // The +50 is applied to the score in every case — the gate acts
                // on the tier, never on the arithmetic.
                #expect(folded.score == 30 + VerifyEvidenceScoring.verifyBothPassWeight)

                if coverage == 0 {
                    #expect(folded.tier == .verified, "\(family): full coverage failed to overrule")
                    #expect(
                        folded.whySuggested.contains { $0.contains("pin overruled") },
                        "the overrule must be disclosed — CLAUDE.md binding guardrail"
                    )
                } else {
                    #expect(
                        folded.tier == .possible,
                        "\(family): coverage \(String(describing: coverage)) overruled the pin"
                    )
                    #expect(!folded.whySuggested.contains { $0.contains("pin overruled") })
                }
            }
        }
    }

    /// The ungated families are unaffected by the carve-out — "non-gated
    /// families are unaffected (`gatedTier == ungatedTier`)". Their promotion
    /// must depend on the score alone, and in particular must **not** acquire a
    /// coverage precondition: idempotence at `.likely` promotes to `.verified`
    /// on a partial bothPass, which is the relaxed-partial-exploration
    /// decision (cycle 124) working as designed.
    @Test("an ungated family's promotion does not depend on coverage")
    func ungatedPromotionIgnoresCoverage() {
        let coverages: [Int?] = [0, 2, nil]
        for family in Self.ungatedFamilies {
            var tiers: Set<Tier> = []
            for coverage in coverages {
                let pick = Self.suggestion(family: family, score: 40)
                let folded = InteractionVerifyEvidenceScoring.applied(
                    to: [pick],
                    evidenceByIdentity: Self.evidence(
                        for: pick,
                        outcome: .measuredBothPass,
                        excludedActionCount: coverage
                    )
                )[0]
                tiers.insert(folded.tier)
                // 40 + 50 = 90 → .strong → promoted to .verified.
                #expect(folded.tier == .verified, "\(family) at coverage \(String(describing: coverage))")
            }
            #expect(tiers.count == 1, "\(family) let coverage change its tier")
        }
    }

    /// A `bothPass` never *lowers* the score, and a fold never rewrites the
    /// identity, family, or predicate it was handed. The second half matters
    /// more than it looks: `identity` is the join key against
    /// `verify-evidence.json` and `decisions.json`, so a fold that re-derived it
    /// would silently orphan every downstream record.
    @Test("the fold never lowers a bothPass score, nor rewrites identity")
    func foldPreservesIdentityAndRaisesScore() {
        for family in InteractionInvariantFamily.allCases {
            for score in [0, 30, 40, 80] {
                let pick = Self.suggestion(family: family, score: score)
                let folded = InteractionVerifyEvidenceScoring.applied(
                    to: [pick],
                    evidenceByIdentity: Self.evidence(
                        for: pick,
                        outcome: .measuredBothPass,
                        excludedActionCount: 0
                    )
                )[0]
                #expect(folded.score > pick.score)
                #expect(folded.identity == pick.identity)
                #expect(folded.family == pick.family)
                #expect(folded.predicate == pick.predicate)
                #expect(folded.firstSeenAt == pick.firstSeenAt)
            }
        }
    }

    /// **The fold is NOT idempotent, and this pins that.**
    ///
    /// Applying it twice adds the +50 twice. That is not a defect today — the
    /// docstring is explicit that the render path "runs it once … before the
    /// visibility cut" — but it is an invitation, because the fold is a pure
    /// function on values with no marker saying it has already run, and the
    /// obvious future change (folding evidence into the SemanticIndex as well as
    /// the render path) would double-count silently and promote picks the gate
    /// was holding down.
    ///
    /// Recorded rather than fixed: making the fold idempotent means giving
    /// `InteractionInvariantSuggestion` a "already graded" marker, which is a
    /// persistence change. The road test's job is to find the sharp edge and
    /// leave it visible.
    @Test("the fold is not idempotent — double-folding double-counts")
    func foldIsNotIdempotent() {
        let pick = Self.suggestion(family: .idempotence, score: 40)
        let evidence = Self.evidence(for: pick, outcome: .measuredBothPass, excludedActionCount: 0)
        let once = InteractionVerifyEvidenceScoring.applied(to: [pick], evidenceByIdentity: evidence)
        let twice = InteractionVerifyEvidenceScoring.applied(to: once, evidenceByIdentity: evidence)

        #expect(once[0].score == 90)
        #expect(twice[0].score == 140, "the +50 is applied again")
        #expect(twice != once, "the fold must be run exactly once — there is no guard against a second")
    }
}
