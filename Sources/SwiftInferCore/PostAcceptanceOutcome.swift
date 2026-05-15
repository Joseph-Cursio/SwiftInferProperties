import Foundation

/// V1.72 — outcome of a `swift-infer accept-check` re-run on a
/// previously-accepted suggestion. The post-acceptance counterpart to
/// `VerifyEvidenceOutcome`, but classified at a coarser, semantically-
/// distinct grain because the question is different:
///
///   - `VerifyEvidenceOutcome` answers "does the property hold right
///     now on this suggestion?" — the pre-acceptance signal.
///   - `PostAcceptanceOutcomeKind` answers "did the property the user
///     accepted *still hold* after the function evolved?" — the
///     regression signal that PRD §17.2's 5th metric needs.
///
/// Four-state classification:
///
///   - `stillPasses` — re-verify returned `measuredBothPass` or
///     `measuredEdgeCaseAdvisory`. The accepted property still holds.
///   - `nowFails` — re-verify returned `measuredDefaultFails`. The
///     property the user accepted is now disproven (regression
///     detected — this is the signal PRD §17.2 is really after).
///   - `obsolete` — the accepted suggestion's identity hash no longer
///     surfaces in the current SemanticIndex (function renamed,
///     removed, or evolved past the suggestion shape). Not a failure;
///     informative — and not a denominator entry for the rate.
///   - `error` — the re-verify gesture could not produce a verdict
///     (build failure, unsupported template/carrier/pair, runtime
///     error, or `architecturalCoveragePending`). Not measurable on
///     this run; excluded from the rate denominator.
///
/// **Why coarser than the five `VerifyEvidenceOutcome` states.** The
/// post-acceptance question collapses `bothPass` + `edgeCaseAdvisory`
/// (both = "property holds") and folds `measuredError` +
/// `architecturalCoveragePending` into one `error` bucket (both =
/// "couldn't measure"). The `obsolete` state has no
/// `VerifyEvidenceOutcome` analog — verify itself never reaches that
/// classification (it throws `.suggestionNotFound`), so the
/// accept-check command synthesizes it from the caught error.
public enum PostAcceptanceOutcomeKind: String, Sendable, Equatable, Codable, CaseIterable {
    case stillPasses = "still-passes"
    case nowFails = "now-fails"
    case obsolete
    case error
}
