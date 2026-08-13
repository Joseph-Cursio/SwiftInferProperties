import Foundation
@testable import SwiftInferCLI
@testable import SwiftInferCore
import Testing

/// Guards the refutation surface added 2026-08-13.
///
/// `verifyDisproven` is a correct full veto, so a refuted pick lands at `.suppressed` and is
/// dropped before the tier cut — silently. On `SwiftFormatRuleStudioCore` the toolchain
/// executed one law of nineteen, that law refuted, the refutation was a real contract
/// violation, and after `verify` recorded it `discover` showed nothing at all
/// (`docs/measurements/exploratory-swiftformatrulestudio.md` §4).
///
/// **The arm that matters is `refutedIsNotTheSuppressedTier`.** Widening the filter from the
/// `verifyDisproven` signal to `.suppressed` would report coverage-vetoed and heuristically
/// suppressed picks as measured refutations — presenting inference as execution, which is a
/// worse error than the silence this fixes.
@Suite("Refutation visibility")
struct RefutationVisibilityTests {

    private func suggestion(
        template: String,
        signals: [Signal],
        subject: String = "parse(_:)"
    ) -> Suggestion {
        var candidate = Suggestion(
            templateName: template,
            evidence: [
                Evidence(
                    displayName: subject,
                    signature: "(String) -> Self",
                    location: SourceLocation(file: "/tmp/Config.swift", line: 61, column: 5)
                )
            ],
            score: Score(signals: signals),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "\(template)|\(subject)")
        )
        candidate.carrierTypeName = "SwiftFormatConfig"
        return candidate
    }

    private var disprovenSignal: Signal {
        Signal(
            kind: .verifyDisproven,
            weight: Signal.vetoWeight,
            detail: "Verify: defaultFails — trial=27"
        )
    }

    // MARK: - Selection

    @Test("a verify-disproven pick is selected")
    func disprovenIsSelected() {
        let picks = [suggestion(template: "round-trip", signals: [disprovenSignal])]
        #expect(RefutationRenderer.refuted(in: picks).count == 1)
    }

    @Test("refuted means the SIGNAL, not the suppressed tier")
    func refutedIsNotTheSuppressedTier() {
        // A coverage veto also lands a pick at `.suppressed`. It is inference — the kit is
        // assumed to check the law — and reporting it as "executed and refuted" would claim a
        // measurement that never happened.
        let coverageVetoed = suggestion(
            template: "commutativity",
            signals: [
                Signal(
                    kind: .protocolCoveredProperty,
                    weight: Signal.vetoWeight,
                    detail: "kit covers this"
                )
            ]
        )
        #expect(coverageVetoed.score.tier == .suppressed)
        #expect(RefutationRenderer.refuted(in: [coverageVetoed]).isEmpty)
    }

    @Test("a passing pick is not selected")
    func passingIsNotSelected() {
        let held = suggestion(
            template: "round-trip",
            signals: [Signal(kind: .verifyBothPass, weight: 50, detail: "held")]
        )
        #expect(RefutationRenderer.refuted(in: [held]).isEmpty)
    }

    // MARK: - Rendering

    @Test("the block names the subject, its file:line, the counterexample and the identity")
    func blockCarriesWhatAReaderNeeds() {
        // Each of these is a thing the reader had to open `verify-evidence.json` to learn.
        let rendered = RefutationRenderer.render(
            [suggestion(template: "round-trip", signals: [disprovenSignal])]
        )
        #expect(rendered.contains("REFUTED BY MEASUREMENT"))
        #expect(rendered.contains("round-trip"))
        #expect(rendered.contains("parse(_:)"))
        #expect(rendered.contains("/tmp/Config.swift:61"))
        #expect(rendered.contains("trial=27"))
    }

    @Test("the block says a refutation is NOT a suggestion")
    func blockDisclaimsSuggestionStatus() {
        // A refuted law must never read as something to go and write. It has been measured
        // false; the open question is only whether the code or the conjecture is wrong.
        let rendered = RefutationRenderer.render(
            [suggestion(template: "round-trip", signals: [disprovenSignal])]
        )
        #expect(rendered.contains("NOT suggestions"))
        #expect(rendered.contains("real defect"))
        #expect(rendered.contains("false conjecture"))
    }

    @Test("nothing refuted renders nothing")
    func emptyRendersEmpty() {
        #expect(RefutationRenderer.render([]).isEmpty)
    }

    // MARK: - It reaches the output

    @Test("the refutation survives --stats-only, which is what CI reads")
    func survivesStatsOnly() {
        // The load-bearing rendering arm. Advisory blocks are gated on `!statsOnly` because
        // they are proposals; a refutation is a RESULT, and hiding a measured counterexample
        // from the view CI reads is the defect one channel along.
        for statsOnly in [true, false] {
            let output = CapturingDiscoverOutput()
            SwiftInferCommand.Discover.renderAndWrite(
                visible: [],
                statsOnly: statsOnly,
                evidenceByIdentity: [:],
                refutedLaws: [suggestion(template: "round-trip", signals: [disprovenSignal])],
                output: output
            )
            #expect(
                output.written.contains("REFUTED BY MEASUREMENT"),
                "statsOnly=\(statsOnly) dropped the refutation"
            )
        }
    }

    @Test("a run with zero suggestions still shows the refutation")
    func survivesEmptySuggestionList() {
        // The exact measured shape: everything else declined, one law ran, it refuted. If the
        // block rode on the suggestion list this would print nothing — which is the bug.
        let output = CapturingDiscoverOutput()
        SwiftInferCommand.Discover.renderAndWrite(
            visible: [],
            statsOnly: false,
            evidenceByIdentity: [:],
            refutedLaws: [suggestion(template: "round-trip", signals: [disprovenSignal])],
            output: output
        )
        #expect(output.written.contains("REFUTED BY MEASUREMENT"))
    }

    @Test("no refutation leaves the output byte-identical to before")
    func absentRefutationChangesNothing() {
        // The control. A block that appears when there is nothing to report would be noise on
        // every clean run, and clean runs are the common case.
        let withEmpty = CapturingDiscoverOutput()
        SwiftInferCommand.Discover.renderAndWrite(
            visible: [], statsOnly: false, evidenceByIdentity: [:],
            refutedLaws: [], output: withEmpty
        )
        let withDefault = CapturingDiscoverOutput()
        SwiftInferCommand.Discover.renderAndWrite(
            visible: [], statsOnly: false, evidenceByIdentity: [:], output: withDefault
        )
        #expect(withEmpty.written == withDefault.written)
        #expect(!withEmpty.written.contains("REFUTED"))
    }
}

/// Collects what `renderAndWrite` produced, so the assertions are about real rendered output
/// rather than about a helper that only the test calls.
private final class CapturingDiscoverOutput: DiscoverOutput, @unchecked Sendable {
    private(set) var written = ""

    func write(_ text: String) {
        written = text
    }
}
