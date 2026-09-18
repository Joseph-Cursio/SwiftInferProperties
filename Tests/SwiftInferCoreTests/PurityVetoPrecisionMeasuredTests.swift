import Foundation
import Testing

@testable import SwiftInferCore
@testable import SwiftInferTemplates

/// **What would a purity veto cost?**
///
/// `docs/measurements/purity-refactoring-reach.md` measured the veto's *population* — the
/// suggestions resting on a subject this analyzer refutes — and said outright that its
/// precision was not measured. This is that measurement.
///
/// ## "False positive" has to be defined before it can be counted
///
/// A veto's cost is the good laws it removes. But **`measured-bothPass` does not mean the
/// property holds** — CLAUDE.md is explicit that it means *no counterexample in the
/// generated domain* — and for an impure subject that is exactly the ambiguous case: a
/// `predicate` law over `isDirectory(_:)` can pass because the filesystem cooperated.
/// Counting every pass as a good law would assume the answer this census exists to test.
///
/// So removals are split, and only one bucket is an unambiguous loss:
///
/// - **`refuted`** — the law found a counterexample. Real work, clearly lost.
/// - **`passed`** — it ran and did not refute. Ambiguous, and suspect exactly where the
///   subject is impure.
/// - **`inert`** — it never ran. Removing it costs nothing measurable.
/// - **`unrecorded`** — not in the answer key at all.
///
/// ## Two scopes, because that is the decision
///
/// The refactoring-reach census recommended scoping the veto to **witness-bearing**
/// refutations rather than vetoing on `.refuted` outright. That is an argument until the
/// two scopes are priced against each other.
///
/// ## The answer key is recorded, stale, and joined exactly
///
/// `fixtures/whole-corpus-survey/2026-09-17-whole-corpus.jsonl` — 633 rows, 200 of which
/// executed. The corpus moves after every survey, so the match rate is asserted rather than
/// assumed: a join resolving almost nothing would report a veto that costs almost nothing,
/// which is the most flattering possible artefact of a broken instrument.
///
/// ⚠ **Re-taken 2026-09-17 because this control went red, and that was it working.** The
/// census first joined the 2026-08-05 stream (281 rows). #494 then put the full signature into
/// every suggestion identity, which rehashed `input-totality` among others, so two removals the
/// old stream had priced (`parse`, `parseBudget`) no longer matched it and read `unrecorded` —
/// 11 of 23 priced, one short of half. The survey was re-taken rather than the bar lowered: a
/// stale answer key under a new identity scheme is the defect the control exists to catch.
///
/// ⚠ **THE WITNESS-SCOPED ARM IS PERMANENTLY UNPRICEABLE, and the suite no longer pretends
/// otherwise** (#514). The veto shipped 2026-08-18 and suppresses exactly the scoped population
/// before the index is built, so no survey taken since contains a row for it — 0 of 10 on
/// 2026-09-17. **Re-taking the key does not help, and neither does the pre-veto one**: joined
/// against the 2026-08-05 stream the scoped arm prices 3 of 10, below the bar this suite's own
/// control sets, so the historical verdict cannot be re-derived from it either.
///
/// **What replaced the three vacuous assertions is the COMPLEMENT.** The rows scoping *spares*
/// are the non-witness-bearing ones — precisely the rows the veto did not suppress, so they are
/// in the index and they are priced. Scoping's value is a fact about them, and `Arm.spared` asks
/// them directly instead of deriving it as `broad − narrow`, where the second term is a zero
/// meaning *priced nothing*. The 2026-08-18 scoped verdict stands as a DATED result.
///
/// `theScopedArmIsUnpriceable` now guards the mechanism, so the arm cannot go quietly vacuous a
/// second time — and it goes red exactly when re-pricing becomes possible again.
///
/// Joined on `SuggestionIdentity.display`, which *is* the survey's `identityHash` — an
/// exact key, not a name. Name-keying has been the dominant defect at this seam in three
/// measurements, and `isDirectory(_:)` alone has two declarations here.
@Suite("Census — what would a purity veto cost?", .serialized)
struct PurityVetoPrecisionMeasuredTests {

    /// **The control guards one threat: a join that resolves nothing reports a veto that
    /// costs nothing.** The quantity that matters for that threat is what fraction of the
    /// *removals* are priced — not what fraction of the corpus is.
    ///
    /// **This control fired on its first run and was corrected rather than relaxed**, and
    /// the distinction is the point. It first asserted that half of all 712 suggestions had
    /// a survey row; 274 do, and the gap is not drift. The survey is *"281 records, one per
    /// **index** entry"* — a filtered population, never a map of every suggestion — so the
    /// original assertion compared a discover population against an index one and would
    /// have failed at any corpus size. What it should assert, and now does, is that the
    /// rows being priced are mostly priced.
    @Test("control — the answer key loaded, and the removals are mostly priced")
    func theAnswerKeyResolves() {
        #expect(Self.survey.count > 200, "the survey loaded \(Self.survey.count) rows; expected ~633")
        #expect(Self.measured.suggestions > 0, "no suggestions discovered — every number is vacuous")

        let priced = Self.measured.spared.filter { $0.cost != .unrecorded }.count
        #expect(priced * 2 > Self.measured.spared.count, """
        Only \(priced) of \(Self.measured.spared.count) SPARED removals carry a recorded \
        outcome. Below half, this census is reporting mostly `unrecorded` and the veto's cost is \
        understated — re-take the survey rather than quoting the small number.
        """)
    }

    /// **The second control, and the suite went vacuous for a month without it** (#514).
    ///
    /// The scoped population is what the shipped veto suppresses, and a suppressed suggestion
    /// never reaches the index the survey enumerates — so the scoped arm cannot be priced by any
    /// survey taken after the veto shipped on 2026-08-18. **That is asserted here rather than
    /// left as a footnote**, because the failure it guards is silence: three assertions read a
    /// zero that meant *priced nothing* as though it meant *costs nothing*, and nothing went red.
    ///
    /// **If this goes RED the veto has stopped suppressing** — rows are reaching the index again,
    /// which is exactly when re-pricing the scoped arm becomes possible. Re-derive the 2026-08-18
    /// verdict then, and restore the comparisons this issue removed.
    @Test("control — the scoped arm is unpriceable, by the veto's own doing")
    func theScopedArmIsUnpriceable() {
        let priced = Self.measured.narrow.filter { $0.cost != .unrecorded }
        #expect(priced.isEmpty, """
        \(priced.count) of \(Self.measured.narrow.count) witness-scoped removals now carry a \
        recorded outcome: \(priced.map(\.subject).joined(separator: ", ")). The shipped veto is \
        no longer suppressing them before the index is built, so the scoped arm can be priced \
        again — re-derive it rather than deleting this control.
        """)
    }

    @Test("the veto has something to remove")
    func theVetoRemovesSomething() {
        #expect(!Self.measured.removals.isEmpty, """
        No suggestion rests on a refuted subject, so there is no veto to price. That \
        contradicts `docs/measurements/purity-refactoring-reach.md` — check whether a veto \
        already landed.
        """)
    }

    /// **The reason the census recommended scoping.** A veto on `.refuted` outright removes
    /// strictly more than one scoped to witness-bearing refutations.
    /// ⚠ **Structural only, deliberately.** This asserted `narrow.passed <= broad.passed` and
    /// `narrow.refuted <= broad.refuted` until #514; both held because the narrow arm is
    /// unpriced and every count on it is zero. A comparison against an unpriceable arm cannot
    /// fail, so what remains is the partition, which is a real claim about the scope predicate.
    @Test("the narrow scope is a strict subset of the naive one")
    func narrowingTheScopeCostsLess() {
        #expect(Self.measured.narrow.count <= Self.measured.removals.count)
        #expect(
            Self.measured.narrow.count + Self.measured.spared.count
                == Self.measured.removals.count,
            """
            The two scopes do not partition the removals, so `spared` is not the complement of \
            `narrow` and every number read off it is describing some other population.
            """
        )
        #expect(!Self.measured.spared.isEmpty, """
        Scoping now spares nothing — the two scopes have become the same veto, and the \
        recommendation to scope has no cost difference left to rest on.
        """)
    }

    /// **The headline, pinned.** Neither scope removes a law that found a counterexample —
    /// so no veto here costs a refutation, which is the only unambiguous loss. If this goes
    /// red, a veto has acquired a real price and the doc's recommendation must be re-read
    /// rather than followed.
    @Test("no veto scope removes a law that found a counterexample")
    func noVetoScopeRemovesARefutingLaw() {
        let broad = Self.counts(Self.measured.removals)[.refuted] ?? 0
        let spared = Self.counts(Self.measured.spared)[.refuted] ?? 0
        #expect(broad == 0, """
        Vetoing on `.refuted` outright would now remove \(broad) law(s) that found a \
        counterexample. That is the unambiguous loss this census measured as zero.
        """)
        // The SPARED half restated, because the broad zero above is only as strong as its
        // priced rows and the scoped ones contribute nothing to it. This one is entirely
        // priced, so it is a claim rather than an absence of evidence.
        #expect(spared == 0)
    }

    /// The scoped veto's whole value in one number: the passing laws it spares.
    ///
    /// ⚠ **Counted on the spared rows DIRECTLY, not as broad − narrow** (#514). The subtraction
    /// gave the same answer here and gave it for the wrong reason: the narrow term is
    /// unpriceable, so `broad > narrow` reduced to `broad > 0` and would have read 11 as
    /// *scoping spares 11* even if scoping had spared nothing. The complement is priced, so
    /// asking it is both a correct derivation and a falsifiable one.
    @Test("scoping spares the codable-round-trip passes")
    func scopingSparesThePasses() {
        let sparedPasses = Self.counts(Self.measured.spared)[.passed] ?? 0
        #expect(sparedPasses > 0, """
        Scoping the veto spares \(sparedPasses) passing laws. The recommendation to scope \
        rests on that number being positive — at zero, the two scopes cost the same.
        """)
    }

    /// **The shipped veto and the scope this census prices must be the same population.**
    /// They are computed by different code — the census applies the rule itself, the veto
    /// runs inside `TemplateRegistry.discover` — so nothing but this assertion stops them
    /// drifting, and a drifted pair would mean the doc prices a veto that is not the one
    /// shipping.
    @Test("the shipped veto suppresses exactly the scoped population")
    func theShippedVetoMatchesTheScope() throws {
        let root = PurityRefutationCensusMeasuredTests.packageRoot.appendingPathComponent("Sources")
        let scanned = try FunctionScanner.scanCorpus(directory: root)
        let suggestions = TemplateRegistry.discover(
            in: scanned.summaries, identities: scanned.identities, typeDecls: scanned.typeDecls
        )
        let vetoed = suggestions.filter { suggestion in
            suggestion.score.signals.contains { $0.kind == .impureSubject && $0.isVeto }
        }

        #expect(vetoed.count == Self.measured.narrow.count, """
        The shipped veto suppressed \(vetoed.count) suggestions; this census prices \
        \(Self.measured.narrow.count). The doc is then describing a different veto from \
        the one that ships.
        """)
        #expect(vetoed.allSatisfy { $0.score.tier == .suppressed }, "a veto did not collapse the tier")
        #expect(vetoed.allSatisfy { suggestion in
            suggestion.explainability.whyMightBeWrong.contains { $0.hasSuffix("(veto)") }
        }, "a vetoed suggestion does not say why it was withheld")
    }

    @Test("census — what a purity veto would cost")
    func census() {
        let arm = Self.measured
        print("""
        self (Sources/): \(arm.suggestions) suggestions · \(arm.recorded) with a 2026-09-17 survey row
          veto on `.refuted` outright — \(arm.removals.count) removed
            \(Self.render(Self.counts(arm.removals)))
          veto scoped to witness-bearing — \(arm.narrow.count) removed  [UNPRICEABLE, #514]
            \(Self.render(Self.counts(arm.narrow)))
          SPARED by scoping — \(arm.spared.count) rows, and these are the priced ones
            \(Self.render(Self.counts(arm.spared)))
        """)
        for removal in arm.removals.sorted(by: { $0.subject < $1.subject }) {
            let scope = removal.witnessBearing ? "W" : "i"
            let cost = removal.cost.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)
            let keyed = Self.survey[removal.identity]
            let named = keyed.map { "[key: \($0.template) :: \($0.function)]" } ?? ""
            print("    \(scope) \(cost) \(removal.template) :: \(removal.subject) \(named)")
        }
    }
}
