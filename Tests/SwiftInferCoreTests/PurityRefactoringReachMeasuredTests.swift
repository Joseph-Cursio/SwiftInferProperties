import Foundation
import Testing

@testable import SwiftInferCore
@testable import SwiftInferTemplates

/// **Would refactoring toward purity put more code within reach of a law?**
///
/// The argument this measures: annotate or refactor toward `@Pure`, and the toolchain
/// finds more property tests. It is a plausible claim about a loop that exists — the
/// tools do read purity, and purity is what makes a generated law meaningful — so it is
/// worth measuring rather than arguing about.
///
/// **Two arms, because checking the first one turned up a better question.**
///
/// - **Arm 1 — the claim in its own terms.** Force every non-`.pure` verdict to `.pure`
///   and re-run discovery. Whatever that moves is the ceiling on "make it pure and the
///   tool finds more", measured with an instrument deliberately more generous than any
///   real refactor: a real one changes the body, this one changes only the verdict.
/// - **Arm 2 — the question arm 1 exposed.** Nothing vetoes a law whose subject the
///   analyzer judges impure. `isInferredPure` has exactly one consumer in shipped code
///   (`EffectAnnotationAdvice`, the outbound advisory) and `purityVerdict` has none, so
///   a template is free to propose a law over a function refuted with a witness. How
///   many of today's suggestions do?
///
/// **The two arms fail in opposite directions**, which is why both are here. If arm 1 is
/// large, purity gates law emission and the refactoring loop is real. If arm 2 is large,
/// purity does not gate it *and should* — the same fact read as a soundness defect
/// rather than a throughput opportunity.
///
/// ## The controls, and why a zero here would otherwise be unreadable
///
/// Arm 1 predicts zero, and this repo has published a zero from a blind detector before
/// (`docs/measurements/module-state-base-rate.md`). Two controls stand behind it:
///
/// 1. **`isThrows` masked** on the same corpora through the same code path must move
///    *something* — item 34 measured +2. That proves the harness reaches the templates.
/// 2. **The join must resolve.** Arm 2 counts suggestions by their subject's verdict, so
///    an evidence row that matches no summary is a hole. The resolve rate is asserted.
@Suite("Census — would refactoring toward purity put more code within a law's reach?", .serialized)
struct PurityRefactoringReachMeasuredTests {

    // MARK: - Controls

    /// Without this, arm 1's zero could mean "purity gates nothing" or "the harness
    /// never reached a template", and those are not the same finding.
    @Test("control — the harness reaches the templates at all")
    func theInstrumentReachesTheTemplates() {
        let moved = Self.measured.map { $0.throwsMasked - $0.baseline }
        #expect(!Self.measured.isEmpty, "no corpus was scanned — every number below is vacuous")
        #expect(moved.contains { $0 != 0 }, """
        Masking `isThrows` across every throwing function moved nothing on any corpus. \
        Item 34 measured +2 through this same path, so either the corpora are not being \
        scanned or the gate has gone — and until that is resolved, arm 1's zero says \
        nothing about purity.
        """)
    }

    /// Arm 2 tallies suggestions by their subject's verdict. An evidence row that
    /// resolves to no summary is silently dropped, so a broken join reports a small,
    /// reassuring number.
    @Test("control — the suggestion-to-summary join resolves")
    func theJoinReachesTheSubjects() {
        for arm in Self.measured {
            #expect(arm.join.evidenceRows > 0, "\(arm.corpus): no evidence rows at all")
            #expect(arm.join.resolvedRows * 4 > arm.join.evidenceRows * 3, """
            \(arm.corpus): only \(arm.join.resolvedRows) of \(arm.join.evidenceRows) evidence \
            rows join to a summary. Below three quarters the verdict tally is measuring \
            the join, not the corpus.
            """)
            #expect(arm.split.unclassified.isEmpty, """
            \(arm.corpus): \(arm.split.unclassified.count) refuted subject(s) could not be \
            re-parsed, so the witness split is over a smaller population than the tally: \
            \(arm.split.unclassified.joined(separator: ", "))
            """)
        }
    }

    // MARK: - Arm 1

    @Test("arm 1 — making every refuted function pure moves no suggestion")
    func makingEveryRefutedFunctionPureMovesNothing() {
        for arm in Self.measured {
            #expect(arm.purityForced == arm.baseline, """
            \(arm.corpus): forcing every verdict to `.pure` moved \
            \(arm.purityForced - arm.baseline) suggestions (\(arm.baseline) → \
            \(arm.purityForced)). Something in the pipeline DOES gate on purity, which \
            reverses this census — find it before quoting the doc.
            """)
        }
    }

    // MARK: - Arm 2

    /// Both directions of the classifier must fire somewhere, or its split is an
    /// artifact. A classifier answering "witness" to everything and one answering
    /// "ignorance" to everything both produce a clean-looking table.
    @Test("control — the witness split is not stuck on one answer")
    func theWitnessSplitIsNotBlind() {
        #expect(Self.measured.contains { !$0.split.witness.isEmpty }, "no witness ever attributed")
        #expect(Self.measured.contains { !$0.split.ignorance.isEmpty }, "no ignorance ever attributed")
    }

    /// **The finding.** Nothing gates law emission on purity, so a template is free to
    /// propose a law over a function this analyzer refutes with a named construct in
    /// the body — a `FileManager` call, a trap, an `async` signature.
    ///
    /// This is the *soundness* reading of the fact arm 1 measures as zero: purity does
    /// not gate law emission, which is why refactoring toward purity frees nothing
    /// **and** why an impure subject is never held back.
    @Test("arm 2 — laws are proposed over subjects refuted with a witness")
    func lawsRestOnWitnessRefutedSubjects() {
        let witnesses = Self.measured.map(\.split.witness.count).reduce(0, +)
        #expect(witnesses > 0, """
        No suggestion on any corpus rests on a witness-refuted subject. That would \
        retire this census's finding — check whether a veto landed before believing it.
        """)
    }

    /// **Item 32's arithmetic, in a fourth place.** The raw count of suggestions
    /// touching a refuted subject over-reports what anything could act on, because a
    /// `propagatedTry` refutation is the analyzer reporting its own blindness rather
    /// than evidence of an impurity — `encode(to:)` is refuted that way ten times over
    /// in this repo's own sources and is not impure.
    @Test("the raw tally over-reports the actionable half")
    func theTallyOverReportsTheWitnessHalf() {
        let witnesses = Self.measured.map(\.split.witness.count).reduce(0, +)
        let all = Self.measured
            .map { $0.split.witness.count + $0.split.ignorance.count + $0.split.computedProperty.count }
            .reduce(0, +)
        #expect(witnesses < all, """
        Every refuted subject under a law now carries a witness (\(witnesses) of \(all)). \
        The tally and the actionable count have converged, so quoting either is safe — \
        which is a change worth re-reading the doc over, not a silent improvement.
        """)
    }

    @Test("arm 2 — suggestions resting on a subject the analyzer refuted")
    func experiment() {
        for arm in Self.measured {
            print("""
            \(arm.corpus): \(arm.summaries) summaries · \(arm.baseline) suggestions
              subjects by verdict — pure \(arm.subjectsPure) · partial \(arm.subjectsPartial) \
            · refuted \(arm.subjectsRefuted)
              suggestions touching a refuted subject: \(arm.join.descriptions.count)
              refuted subjects — witness \(arm.split.witness.count) · ignorance-only \
            \(arm.split.ignorance.count) · computed-property \(arm.split.computedProperty.count) \
            · unclassified \(arm.split.unclassified.count)
              evidence rows \(arm.join.evidenceRows), resolved \(arm.join.resolvedRows)
              isThrows-masked control: \(arm.throwsMasked) (\(arm.throwsMasked - arm.baseline))
              purity-forced arm:       \(arm.purityForced) (\(arm.purityForced - arm.baseline))
            """)
            for row in arm.split.witness { print("    W \(row)") }
            for row in arm.split.ignorance { print("    i \(row)") }
            for row in arm.split.computedProperty { print("    P \(row)") }
            for row in arm.split.unclassified { print("    ? \(row)") }
        }
    }
}
