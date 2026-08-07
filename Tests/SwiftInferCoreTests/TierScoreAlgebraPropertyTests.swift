import Foundation
import PropertyLawKit
import SwiftInferCore
import Testing

// Self-dogfood road test (`docs/measurements/roadtest-self-dogfood.md`) — the confidence
// algebra `swift-infer discover` proposed **nothing** for.
//
// `Tier` and `Score` are the two types the whole tool's output passes through:
// every suggestion's visibility is `Tier(score:)` of a sum of `Signal` weights,
// and PRD §4.2's thresholds are the product's central precision claim. They are
// total functions on tiny value types with unusually explicit docstrings — the
// best property-testing surface in the repo — and `discover` surfaced zero
// candidates on either, because a score-to-tier mapping is not an endomorphism,
// a binary operation, or a round-trip pair. It is out of catalog.
//
// So these laws come the other way: from the documented intent (Chapter 2
// §2.4.2). Every one below quotes a sentence that is already in the source and
// turns it into something that can be false. Where the docstring says "never
// returns `.verified`", that is a law. Where it says the tier ordering "is a
// deliberate declaration, not a side effect of `case`-declaration layout," that
// is a law too — and a sharper one, because reordering the `case` lines is
// exactly the edit that would silently break it.
@Suite("Road test — Tier / Score confidence algebra")
struct TierScoreAlgebraPropertyTests {

    /// Scores span well past the §4.2 thresholds in both directions. The
    /// negative range matters: counter-signals are real (`-25` for a cross-type
    /// round-trip pair), and several of them can stack below zero.
    ///
    /// Used for the *far-field* laws only. The threshold laws below sweep
    /// `boundarySweep` exhaustively instead — see its note for why.
    private static let scoreGen = Gen<Int>.int(in: -200...200)

    /// **Every integer from below the Suppressed floor to above the Strong
    /// floor, swept exhaustively rather than sampled.**
    ///
    /// This is not belt-and-braces; it is a correction. The first version of
    /// this suite stated the threshold laws with `propertyCheck` over
    /// `scoreGen`, and a mutation check — moving `case 40..<75` to
    /// `case 41..<75`, a one-character boundary slip — was caught by only *one*
    /// of the three tests that should have caught it. The reason is arithmetic:
    /// a uniform draw from 401 integers hits the single value 40 about 22% of
    /// the time in 100 trials, so the suite would have reported that mutation
    /// as survived roughly four runs in five.
    ///
    /// The thresholds live in a small contiguous integer domain, and the whole
    /// domain is 141 values. Sampling it is strictly worse than walking it.
    private static let boundarySweep = Array(-10...130)

    private static let tierGen = Gen.element(of: Tier.allCases).map { $0! }

    private static let signalGen = zip(
        Gen.element(of: Signal.Kind.allCases),
        Gen<Int>.int(in: -50...50)
    ).map { kind, weight in
        Signal(kind: kind!, weight: weight, detail: "test")
    }

    private static let signalsGen = signalGen.array(of: 0...6)

    // MARK: - Tier(score:) — the §4.2 threshold mapping

    /// **Monotonicity: a higher score is never assigned a less prominent tier.**
    ///
    /// The single most load-bearing law in the file. `Tier`'s `Comparable` is
    /// ordered by prominence (`verified` is the minimum), so this reads as
    /// `a <= b` implies `Tier(score: b) <= Tier(score: a)`. Every off-by-one at
    /// a threshold boundary, every swapped range, every accidental `..<` for
    /// `...` breaks it — and none of those would be caught by an example test
    /// that happens to sample 10, 50, and 90.
    @Test("Tier(score:) is monotone — more score is never less prominence")
    func tierIsMonotoneInScore() async {
        // Exhaustive on adjacent pairs across the whole threshold domain: this
        // is where a boundary slip actually shows up, and every transition is
        // visited exactly once.
        for (lower, upper) in zip(Self.boundarySweep, Self.boundarySweep.dropFirst()) {
            #expect(Tier(score: upper) <= Tier(score: lower), "monotonicity broke at \(lower) → \(upper)")
        }
        // …and sampled in the far field, where the domain is too big to walk.
        await propertyCheck(input: Self.scoreGen, Self.scoreGen) { lower, higher in
            guard lower <= higher else { return }
            #expect(Tier(score: higher) <= Tier(score: lower))
        }
    }

    /// The thresholds themselves, as a total function rather than as four spot
    /// checks. Refutable by any boundary slip; `Tier(score:)`'s own docstring is
    /// the reference definition.
    @Test("Tier(score:) matches the PRD §4.2 thresholds exactly")
    func tierMatchesDocumentedThresholds() async {
        func expected(_ score: Int) -> Tier {
            score >= 75 ? .strong
                : score >= 40 ? .likely
                : score >= 20 ? .possible
                : .suppressed
        }
        for score in Self.boundarySweep {
            #expect(Tier(score: score) == expected(score), "threshold wrong at \(score)")
        }
        await propertyCheck(input: Self.scoreGen) { score in
            #expect(Tier(score: score) == expected(score))
        }
    }

    /// "Never produces `.verified` or `.advisory` — both are set explicitly by
    /// the surfacing pipeline." Quoted from the initializer's docstring, now
    /// enforced over the whole domain.
    ///
    /// This one guards a real confusion: `.verified` is the *most* prominent
    /// tier and `.advisory` sorts below `.suppressed`, so a future contributor
    /// adding a `case 100...: self = .verified` arm would look reasonable and
    /// would quietly let score alone claim machine-confirmed status.
    @Test("Tier(score:) never returns .verified or .advisory")
    func tierNeverReturnsPipelineOnlyTiers() async {
        await propertyCheck(input: Self.scoreGen) { score in
            #expect(Tier(score: score) != .verified)
            #expect(Tier(score: score) != .advisory)
        }
    }

    /// The default visibility cut and the threshold table have to agree: a
    /// score-derived tier is shown by default exactly when it cleared the
    /// `.likely` floor of 40. Two independent `switch` statements encode this
    /// (`Tier(score:)` and `isVisibleByDefault`) with nothing tying them
    /// together — this is the tie.
    @Test("default visibility agrees with the 40-point Likely floor")
    func visibilityAgreesWithLikelyFloor() async {
        for score in Self.boundarySweep {
            #expect(Tier(score: score).isVisibleByDefault == (score >= 40), "visibility wrong at \(score)")
        }
        await propertyCheck(input: Self.scoreGen) { score in
            #expect(Tier(score: score).isVisibleByDefault == (score >= 40))
        }
    }

    // MARK: - The tier ordering

    /// "The tier ordering is a deliberate declaration, not a side effect of
    /// `case`-declaration layout: reordering the `case` lines can't change it."
    ///
    /// That claim rests entirely on `severityRank` being **injective** — if two
    /// tiers shared a rank they would compare equal under `<` while being
    /// unequal under `==`, `sorted()` would stop being deterministic, and the
    /// canonical display order would depend on input order after all. There is
    /// no compiler check for it. This is that check.
    @Test("the tier ordering is a strict total order — severityRank is injective")
    func tierOrderingIsStrictTotal() async {
        // Antisymmetry with `==`, i.e. injectivity of the underlying rank.
        for lhs in Tier.allCases {
            for rhs in Tier.allCases where lhs != rhs {
                #expect(lhs < rhs || rhs < lhs, "\(lhs) and \(rhs) share a severity rank")
            }
        }
        // …and the kit's Comparable suite for irreflexivity / transitivity /
        // the Equatable laws underneath.
        let results = try? await checkComparablePropertyLaws(
            for: Tier.self,
            using: Self.tierGen,
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results?.allSatisfy { $0.isViolation == false } == true)
    }

    /// `reportDisplayOrder` is documented as derived by sorting `allCases` "so a
    /// new tier can never silently drop out of the breakdown." That is a
    /// permutation law, and it is the one a `swift-infer report` reader depends
    /// on without knowing it — a dropped tier does not render as an error, it
    /// renders as an absent row.
    @Test("reportDisplayOrder is a permutation of allCases")
    func reportDisplayOrderIsAPermutation() {
        let order = Tier.reportDisplayOrder
        #expect(order.count == Tier.allCases.count)
        #expect(Set(order) == Set(Tier.allCases))
    }

    /// Every tier renders a distinct label. `discover`, `report`, and the
    /// decision log all key on `label` as a string; two tiers sharing one would
    /// conflate a machine-confirmed pick with a heuristic guess in every
    /// surface at once, and would do it silently.
    @Test("tier labels are injective")
    func tierLabelsAreInjective() {
        let labels = Tier.allCases.map(\.label)
        #expect(Set(labels).count == labels.count)
    }

    /// `atLeastAsProminentAs(_:)` replaced two hand-kept string lists that had
    /// to match `label` exactly with no compiler check. These are the laws that
    /// justify that replacement: it is monotone in the floor, it always contains
    /// the floor itself, and its membership test is exactly `<=`.
    @Test("atLeastAsProminentAs is monotone, floor-inclusive, and agrees with <=")
    func atLeastAsProminentAsIsWellBehaved() async {
        await propertyCheck(input: Self.tierGen, Self.tierGen) { lower, upper in
            #expect(Tier.atLeastAsProminentAs(lower).contains(lower))
            #expect(Set(Tier.atLeastAsProminentAs(lower)) == Set(Tier.allCases.filter { $0 <= lower }))
            guard lower <= upper else { return }
            // A less prominent floor admits a superset.
            #expect(
                Set(Tier.atLeastAsProminentAs(lower))
                    .isSubset(of: Set(Tier.atLeastAsProminentAs(upper)))
            )
        }
    }

    // MARK: - promoted(byVerifyOutcome:)

    /// "Every other `(tier, outcome)` pair — including a `nil` outcome — returns
    /// `self` unchanged." Stated over the full cross product of tiers and
    /// outcomes, plus `nil`, rather than the two cases an example test reaches.
    @Test("promotion fires only for .strong + .measuredBothPass")
    func promotionFiresOnlyForStrongBothPass() {
        let outcomes: [VerifyEvidenceOutcome?] = [nil] + Array(VerifyEvidenceOutcome.allCases)
        for tier in Tier.allCases {
            for outcome in outcomes {
                let promoted = tier.promoted(byVerifyOutcome: outcome)
                if tier == .strong, outcome == .measuredBothPass {
                    #expect(promoted == .verified)
                } else {
                    #expect(promoted == tier, "\(tier) + \(String(describing: outcome)) moved")
                }
            }
        }
    }

    /// Promotion is idempotent and never demotes — it is a monotone closure
    /// operator on the tier lattice. Folding verify evidence twice (the render
    /// path and, say, a future index-side pass) must not compound.
    @Test("promotion is idempotent and never demotes")
    func promotionIsIdempotentAndMonotone() async {
        await propertyCheck(input: Self.tierGen) { tier in
            for outcome in VerifyEvidenceOutcome.allCases {
                let once = tier.promoted(byVerifyOutcome: outcome)
                #expect(once.promoted(byVerifyOutcome: outcome) == once)
                #expect(once <= tier, "promotion made a tier less prominent")
            }
        }
    }

    // MARK: - Score

    /// "The total is the sum of non-veto weights." Stated as a law over
    /// arbitrary signal bags, including bags containing vetoes — which is the
    /// case that matters, since `Signal.vetoWeight` is `Int.min` and summing it
    /// in would overflow rather than merely mis-score.
    @Test("Score.total is the sum of non-veto weights")
    func totalIsSumOfNonVetoWeights() async {
        await propertyCheck(input: Self.signalsGen) { signals in
            let expected = signals.filter { !$0.isVeto }.map(\.weight).reduce(0, +)
            #expect(Score(signals: signals).total == expected)
        }
    }

    /// **The precision invariant: "a vetoed score always maps to `.suppressed`
    /// regardless of total."**
    ///
    /// This is the law that keeps a false positive off the default surface. A
    /// veto has to beat any accumulation of positive signals, so the test forces
    /// exactly that collision — a full-weight veto dropped into a bag that would
    /// otherwise score `Strong`.
    @Test("a veto collapses to .suppressed regardless of total")
    func vetoCollapsesRegardlessOfTotal() async {
        let veto = Signal(kind: .nonDeterministicBody, weight: Signal.vetoWeight, detail: "veto")
        await propertyCheck(input: Self.signalsGen, Gen<Int>.int(in: 0...6)) { signals, position in
            var withVeto = signals.filter { !$0.isVeto }
            // Pile on enough positive weight that an unvetoed bag would be Strong.
            withVeto.append(Signal(kind: .exactNameMatch, weight: 100, detail: "big"))
            withVeto.insert(veto, at: min(position, withVeto.count))
            let score = Score(signals: withVeto)
            #expect(score.isVetoed)
            #expect(score.tier == .suppressed)
        }
    }

    /// The total does not depend on signal order, but the recorded `signals` do
    /// — "order is preserved so the renderer can present them in a stable,
    /// template-defined sequence." Two halves of one docstring, and they pull in
    /// opposite directions, so both are worth pinning.
    @Test("Score is order-invariant in total and order-preserving in signals")
    func scoreIsOrderInvariantButOrderPreserving() async {
        await propertyCheck(input: Self.signalsGen) { signals in
            #expect(Score(signals: signals).signals == signals)
            #expect(Score(signals: signals.reversed()).total == Score(signals: signals).total)
            #expect(Score(signals: signals.reversed()).tier == Score(signals: signals).tier)
        }
    }

    /// Scoring is additive over concatenation when neither bag vetoes — the
    /// homomorphism that makes "signals are independent per PRD §4.1" true in
    /// the arithmetic and not just in the prose. It is what lets a template add
    /// a signal without recomputing anything.
    @Test("Score.total is additive over concatenation (no vetoes)")
    func totalIsAdditiveOverConcatenation() async {
        await propertyCheck(input: Self.signalsGen, Self.signalsGen) { lhs, rhs in
            let left = lhs.filter { !$0.isVeto }
            let right = rhs.filter { !$0.isVeto }
            #expect(Score(signals: left + right).total == Score(signals: left).total + Score(signals: right).total)
        }
    }

    /// `Score(advisorySignals:)` carries an **unenforced precondition**:
    /// "vetoed signals are not allowed … callers ensure no `.isVeto` signals
    /// reach this path." Unlike `init(signals:)`, this initializer does not
    /// filter — it sums every weight it is handed.
    ///
    /// Both live call sites (`Discover+GenericLaws`, `LiftedSuggestionPromotion`)
    /// pass a single hand-built non-veto signal, so nothing is broken today.
    /// What this test pins is the shape of the trap for whoever adds the third
    /// call site: one veto signal yields an incoherent `Score` — `.advisory`
    /// tier, `isVetoed == false`, and a total of `Int.min` — and **two** veto
    /// signals overflow the `reduce(0, +)` and trap outright. The two-veto case
    /// is deliberately described rather than executed; a test that crashes the
    /// process documents nothing.
    @Test("Score(advisorySignals:) does not filter vetoes — an unenforced precondition")
    func advisoryInitDoesNotFilterVetoes() async {
        await propertyCheck(input: Self.signalsGen) { signals in
            let clean = signals.filter { !$0.isVeto }
            let score = Score(advisorySignals: clean)
            #expect(score.tier == .advisory)
            #expect(score.isVetoed == false)
            #expect(score.signals == clean)
        }

        // The precondition violation, characterized at its safe boundary.
        let veto = Signal(kind: .verifyDisproven, weight: Signal.vetoWeight, detail: "veto")
        let incoherent = Score(advisorySignals: [veto])
        #expect(incoherent.tier == .advisory)
        #expect(incoherent.isVetoed == false, "a veto signal present, yet the score says otherwise")
        #expect(incoherent.total == Int.min, "…and the total is a sentinel, not a weight")
    }

    /// Round-trip laws for the persisted tier vocabulary. `Tier` is written into
    /// `decisions.json`, the SemanticIndex, and `verify-evidence.json`; a raw
    /// value that failed to round-trip would surface as a decode error in the
    /// field, long after the edit that caused it.
    @Test("Tier round-trips through Codable and RawRepresentable")
    func tierRoundTrips() async throws {
        let codable = try await checkCodablePropertyLaws(
            for: Tier.self,
            using: Self.tierGen,
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(codable.allSatisfy { $0.isViolation == false })

        let raw = try await checkRawRepresentablePropertyLaws(
            for: Tier.self,
            using: Self.tierGen,
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(raw.allSatisfy { $0.isViolation == false })
    }
}
