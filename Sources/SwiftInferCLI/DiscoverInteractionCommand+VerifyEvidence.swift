import Foundation
import SwiftInferCore

extension SwiftInferCommand.DiscoverInteraction {

    /// Cycle 112 — the verify-evidence consumer (the M9 join's read side).
    /// Loads `.swiftinfer/verify-evidence.json` (written by
    /// `verify-interaction`, cycle 111) and folds each measured outcome
    /// into the suggestion grade via `InteractionVerifyEvidenceScoring` —
    /// a `.measuredBothPass` lifts idempotence off `.likely`, a
    /// `.measuredDefaultFails` suppresses. Best-effort: a load/parse
    /// warning is surfaced via `diagnostics`, never fatal; an absent file
    /// yields an empty map and the suggestions pass through unchanged.
    ///
    /// Applied on the **render path only** (`run` / `runPipeline`), not
    /// inside `collectSuggestions` — that leg is shared with
    /// `drift-interaction`'s baseline diff, which must keep the pre-verify,
    /// score-derived tier (a baseline snapshot is a surface marker, not a
    /// verified decision). Mirrors the algebraic `loadVerifyEvidenceMap`
    /// in `SwiftInferCommand`. File-split to keep the command file under
    /// the SwiftLint file-length cap.
    static func gradedByVerifyEvidence(
        _ suggestions: [InteractionInvariantSuggestion],
        workingDirectory: URL,
        diagnostics: any DiagnosticOutput
    ) -> [InteractionInvariantSuggestion] {
        let evidenceResult = VerifyEvidenceStore.load(startingFrom: workingDirectory)
        for warning in evidenceResult.warnings {
            diagnostics.writeDiagnostic("warning: \(warning)")
        }
        let evidenceByIdentity = Dictionary(
            evidenceResult.log.records.map { ($0.identityHash, $0) }
        ) { _, latest in latest }
        return InteractionVerifyEvidenceScoring.applied(
            to: suggestions,
            evidenceByIdentity: evidenceByIdentity
        )
    }
}
