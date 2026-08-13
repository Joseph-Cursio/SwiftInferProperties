import Foundation
import SwiftInferCore

/// The block that shows a law **execution refuted**, on stdout, where a reader is looking.
///
/// ## The defect this closes
///
/// `verifyDisproven` is a full veto — correctly, since a measured counterexample means the law
/// is genuinely wrong rather than merely low-confidence. So a refuted pick lands at
/// `.suppressed` and `Discover+Pipeline` drops it, deliberately, before the tier cut.
///
/// The suppression was silent. On `SwiftFormatRuleStudioCore`
/// (`docs/measurements/exploratory-swiftformatrulestudio.md` §4) the whole toolchain executed
/// exactly **one** law of nineteen, that law **refuted**, and the refutation was a real
/// contract violation in the subject. After `verify` recorded it, `discover` printed the row
/// no more — no note, no counterexample, no date. The single most valuable thing the run
/// produced became indistinguishable from having found nothing, and `report` said `Disproven
/// 1`: one digit, no subject.
///
/// **This is `Confident zero` manufactured by the tool's own success.** A reader who runs
/// `discover` → `verify` → `discover` watches a row vanish and reads it as fixed or withdrawn.
///
/// ## Why stdout, when the neighbouring diagnostics are on stderr
///
/// `Discover+EvidenceDiagnostics` exists for the same class of problem — *a grade change can
/// hide its own reason* — and writes to stderr. Its own header records what that cost: the
/// coverage `note:` was invisible through an entire eight-corpus census, because every
/// invocation ran with `2>/dev/null`, **including the runs whose numbers were written into the
/// findings doc**. The fix there was to move the *number* to stdout beside the count.
///
/// A refutation is the strongest evidence this tool ever holds — the only output backed by an
/// executed counterexample rather than inference. Putting it on the channel already measured
/// to be discarded would repeat a mistake this repo has already paid for once.
///
/// ## It is not a suggestion, and is rendered so it cannot be read as one
///
/// A refuted law must never re-enter the suggestion list: it has been measured false. The
/// block is separate, labelled as a refutation, and carries the counterexample — the same
/// separation `DocstringAdvisoryRenderer` and `EffectAnnotationRenderer` already use for
/// output that is not a property-test proposal.
enum RefutationRenderer {

    /// Picks whose score carries the `verifyDisproven` veto.
    ///
    /// Filtered on the **signal**, not on `.suppressed`: several vetoes land a pick in that
    /// tier and only this one means *executed and refuted*. Reporting the tier would sweep in
    /// coverage-vetoed and heuristically-suppressed picks and call them refutations, which is
    /// a far worse error than the silence being fixed.
    static func refuted(in graded: [Suggestion]) -> [Suggestion] {
        graded.filter { suggestion in
            suggestion.score.signals.contains { $0.kind == .verifyDisproven }
        }
    }

    /// The rendered block, or `""` when nothing was refuted.
    static func render(_ refuted: [Suggestion]) -> String {
        guard !refuted.isEmpty else { return "" }
        let heading = refuted.count == 1
            ? "REFUTED BY MEASUREMENT — 1 law was executed and a counterexample was found."
            : "REFUTED BY MEASUREMENT — \(refuted.count) laws were executed and "
                + "counterexamples were found."
        return ([
            heading,
            "These are NOT suggestions and are not proposed again: each was run and failed. A "
                + "refutation is either a real defect in the subject or a false conjecture "
                + "about correct code — read the counterexample and decide which.",
            ""
        ] + refuted.sorted { $0.templateName < $1.templateName }.flatMap(entry))
            .joined(separator: "\n")
    }

    private static func entry(_ suggestion: Suggestion) -> [String] {
        // The subject and its location, because a refutation a reader cannot locate is the
        // same unauditable row §7.4 of the road test complains about, one channel along.
        let subject = suggestion.evidence.first.map {
            "\($0.displayName)  \($0.signature)"
        } ?? (suggestion.carrierTypeName ?? "(subject not recorded)")
        let location = suggestion.evidence.first.map {
            "\n    \($0.location.file):\($0.location.line)"
        } ?? ""
        let detail = suggestion.score.signals
            .first { $0.kind == .verifyDisproven }?
            .detail ?? "disproven by counterexample"
        return [
            "  ✗ \(suggestion.templateName)  \(subject)\(location)",
            "    \(detail)",
            "    Identity: \(suggestion.identity.display)",
            ""
        ]
    }
}
