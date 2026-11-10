import Foundation
import SwiftEffectInference
import Testing

@testable import SwiftInferCore
@testable import SwiftInferTemplates

extension ImpureSubjectVetoTests {

    /// **`.refuted` is `FunctionSummary.init`'s default**, so on a summary nothing analysed
    /// it means *not computed*. Reading that as evidence is item 40's finding — a verdict
    /// that is an initialiser default — arriving at a consumer instead of an advisory.
    ///
    /// **Watched failing.** Before the body-fingerprint gate existed, this veto suppressed
    /// six unrelated suites whose fixtures build summaries by hand: monotonicity
    /// cross-validation, the counter-signal seam, `value-round-trip` end-to-end,
    /// associativity corpus aggregation, `normalize(_:)` at Likely, and the `encode/decode`
    /// pair. Every one of them passes a hand-built summary to `TemplateRegistry.discover`.
    @Test("a defaulted verdict is not evidence — an unanalysed summary is never vetoed")
    func defaultedVerdictIsNotEvidence() {
        let handBuilt = Self.summary(name: "combine", line: 50, verdict: .refuted, analysed: false)
        let kept = Self.apply(handBuilt)

        #expect(!kept.score.signals.contains { $0.kind == .impureSubject }, """
        A summary with no body fingerprint was vetoed. `.refuted` is the initialiser \
        default, so that reads "nobody computed a verdict" as "the verdict is refuted" — \
        and it suppresses every hand-built fixture in the suite.
        """)
        #expect(kept.score.tier != .suppressed)
    }
}
