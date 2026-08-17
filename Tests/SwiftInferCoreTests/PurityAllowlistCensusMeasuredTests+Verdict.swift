import Foundation
import SwiftEffectInference
import Testing

@testable import SwiftInferCore

/// The standing verdict for `PurityAllowlistCensusMeasuredTests`, asserted
/// rather than described so it cannot drift. Exact counts and the tree they were
/// taken on are in `docs/measurements/purity-unrecognised-callee-census.md`.
///
/// Every assertion here is a **direction**, never a literal count — the corpus is
/// this repo's own `Sources/` and grows every commit. What must not drift is
/// which way each number points, because each direction is what warrants (or
/// declines) a specific build.
extension PurityAllowlistCensusMeasuredTests {

    /// **The answer to item 30's first half: the under-refutation is REAL.**
    /// Measured 2026-08-17 — 18 `.pure` verdicts call a package function this
    /// same analyzer refutes with a witness, one hop, by an unambiguous name.
    ///
    /// This is the assertion that separates item 30 from item 40. There the
    /// unchecked claim had a measured error rate of zero and the honest finding
    /// was *narrower* than the filing; here it does not, and the sharpest of the
    /// 18 is `DrainedProcess.standardOutputViaEnv`, which **spawns a
    /// subprocess** and is judged pure. That is the exact disaster
    /// `throwsOnlyItsOwnErrors`' own doc was written about — the `try` route into
    /// a subprocess was closed and the plain-call route was left open.
    ///
    /// The day this reaches zero, the package-internal half of item 30 is closed
    /// and this test is where that is noticed.
    @Test("a .pure verdict can rest on a callee this analyzer itself refutes")
    func theUnderRefutationIsReal() {
        #expect(
            !Self.unsound.isEmpty,
            """
            No .pure subject calls a witness-refuted package function any more. If that is a \
            fix rather than a corpus accident, item 30's package-internal half is closed — \
            see docs/measurements/purity-unrecognised-callee-census.md before deleting this.
            """
        )
    }

    /// **The answer to item 30's second half: the proposed fix is expensive, and
    /// this is the bill.** Flipping the default so an unrecognised callee yields
    /// ignorance rather than a pass moves the *majority* of `.pure` verdicts into
    /// the item 29 bucket — 1,579 of 2,417 when measured — and only a seed set
    /// of asserted axioms brings them back.
    ///
    /// Asserted as "most of them" because that is the fact that makes the
    /// allowlist a build rather than a patch. If it ever falls below half, the
    /// flip is affordable without axioms and the decline recorded in the
    /// measurements doc should be re-opened.
    @Test("most pure verdicts rest on a callee this leaf never examined")
    func flippingTheDefaultMovesMostOfThePurePopulation() {
        let blocked = Self.pureProfiles.filter { !$0.unrecognised.isEmpty }.count
        #expect(
            blocked * 2 > Self.pureProfiles.count,
            "\(blocked) of \(Self.pureProfiles.count) .pure subjects reach an unrecognised callee"
        )
    }

    /// **Item 32's arithmetic, in a second place and about axioms rather than
    /// annotations.** A frequency table over unrecognised callee names reports
    /// how many subjects each name *touches*; a subject is only freed when its
    /// **whole** unrecognised set is admitted. Measured at the top 10, that is
    /// 992 touched against 463 freed.
    ///
    /// The consequence is a rule, not a curiosity: a seed set must be scored by
    /// subjects fully covered. Score it by name frequency and the report promises
    /// roughly twice what the axioms buy.
    @Test("a frequency table over-reports what a seed set actually frees")
    func theFrequencyTableOverReportsTheSeedSet() {
        let coverage = Self.coverage(ofTopMostFrequent: 10, over: Self.profiles)
        #expect(
            coverage.touched > coverage.freed,
            "top 10 axioms: touched \(coverage.touched), freed \(coverage.freed)"
        )
    }

    /// **The price is finite, and that is the surprise.** 508 distinct names hold
    /// the entire non-refuted population of this corpus; greedy-with-recompute
    /// reaches half the blocked rows on 24 axioms and 80% on 131. A
    /// hand-curatable list, not an open-ended one.
    ///
    /// Bounded against the corpus rather than a literal so it scales with the
    /// tree. The direction that matters: if the distinct-callee count ever grows
    /// faster than the population it serves, "assert a seed set" stops being a
    /// build anyone can finish and the measurements doc's costing is void.
    @Test("the seed set that would hold this corpus is small enough to hand-curate")
    func theSeedSetIsFinite() {
        let distinct = Set(Self.profiles.flatMap(\.unrecognised)).count
        #expect(
            distinct * 4 < Self.profiles.count,
            "\(distinct) distinct unrecognised callees over \(Self.profiles.count) subjects"
        )
    }

    /// **The finding this census was not looking for, pinned so the fix
    /// announces itself.** `bodyHasRefutingMarker` is handed `function.body`, and
    /// a default argument lives in the signature — so
    /// `func bridges(…, now: Date = Date())` reads the clock on every call that
    /// omits the argument and is judged `.pure`. Measured: 15 subjects, every one
    /// of them a `Date()` or a `FileManager` read, all hand-checked.
    ///
    /// **This test fails the day the hole is closed, and that is its job** — the
    /// same shape as `computedPropertyAdviceIsAccidentallyCorrect`. It is a
    /// standing claim that the defect is still open, not a claim that it should
    /// be. Closing it means deleting this test in the same commit, which is
    /// exactly the notification a comment would not give.
    @Test("a marker in a default argument is still invisible to the body scan")
    func markersInDefaultArgumentsAreStillMissed() {
        #expect(
            !Self.markerInDefaultArgument.isEmpty,
            """
            No non-refuted subject defaults a parameter to a marker any more. If PurityInferrer \
            learned to scan default values, delete this test with the fix; if the corpus merely \
            stopped exhibiting the shape, the hole is still open and needs a synthetic witness.
            """
        )
        // Every row is a genuine impurity-on-the-default-path, hand-checked at
        // the measured tree. The shape is narrow enough to say so: nothing here
        // is a parameter *type* mentioning a marker, which would be pure.
        for entry in Self.markerInDefaultArgument {
            #expect(
                !entry.markers.isEmpty,
                "\(entry.subject.file):\(entry.subject.name) attributed no marker"
            )
        }
    }
}
