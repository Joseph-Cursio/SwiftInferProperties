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
/// `fixtures/whole-corpus-survey/2026-08-05-whole-corpus.jsonl` — 281 rows, 139 of which
/// executed. It is **13 days older than this measurement** and the corpus has moved, so
/// the match rate is asserted rather than assumed: a join resolving almost nothing would
/// report a veto that costs almost nothing, which is the most flattering possible artefact
/// of a broken instrument.
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
        #expect(Self.survey.count > 200, "the survey loaded \(Self.survey.count) rows; expected ~281")
        #expect(Self.measured.suggestions > 0, "no suggestions discovered — every number is vacuous")

        let priced = Self.measured.removals.filter { $0.cost != .unrecorded }.count
        #expect(priced * 2 > Self.measured.removals.count, """
        Only \(priced) of \(Self.measured.removals.count) removals carry a recorded outcome. \
        Below half, this census is reporting mostly `unrecorded` and the veto's cost is \
        understated — re-take the survey rather than quoting the small number.
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
    @Test("the narrow scope costs no more than the naive one")
    func narrowingTheScopeCostsLess() {
        let broad = Self.counts(Self.measured.removals)
        let narrow = Self.counts(Self.measured.narrow)

        #expect(Self.measured.narrow.count <= Self.measured.removals.count)
        #expect((narrow[.passed] ?? 0) <= (broad[.passed] ?? 0), """
        Scoping the veto to witness-bearing refutations removes MORE passing laws than \
        vetoing on `.refuted` outright, which is arithmetically impossible unless the scope \
        predicate has inverted.
        """)
        #expect((narrow[.refuted] ?? 0) <= (broad[.refuted] ?? 0))
    }

    /// **The headline, pinned.** Neither scope removes a law that found a counterexample —
    /// so no veto here costs a refutation, which is the only unambiguous loss. If this goes
    /// red, a veto has acquired a real price and the doc's recommendation must be re-read
    /// rather than followed.
    @Test("no veto scope removes a law that found a counterexample")
    func noVetoScopeRemovesARefutingLaw() {
        let broad = Self.counts(Self.measured.removals)[.refuted] ?? 0
        let narrow = Self.counts(Self.measured.narrow)[.refuted] ?? 0
        #expect(broad == 0, """
        Vetoing on `.refuted` outright would now remove \(broad) law(s) that found a \
        counterexample. That is the unambiguous loss this census measured as zero.
        """)
        #expect(narrow == 0)
    }

    /// The scoped veto's whole value in one number: the passing laws it spares.
    @Test("scoping spares the codable-round-trip passes")
    func scopingSparesThePasses() {
        let broadPasses = Self.counts(Self.measured.removals)[.passed] ?? 0
        let narrowPasses = Self.counts(Self.measured.narrow)[.passed] ?? 0
        #expect(broadPasses > narrowPasses, """
        Scoping the veto no longer spares any passing law (\(broadPasses) → \(narrowPasses)). \
        The recommendation to scope rests on that gap.
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
        self (Sources/): \(arm.suggestions) suggestions · \(arm.recorded) with a 2026-08-05 survey row
          veto on `.refuted` outright — \(arm.removals.count) removed
            \(Self.render(Self.counts(arm.removals)))
          veto scoped to witness-bearing — \(arm.narrow.count) removed
            \(Self.render(Self.counts(arm.narrow)))
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
