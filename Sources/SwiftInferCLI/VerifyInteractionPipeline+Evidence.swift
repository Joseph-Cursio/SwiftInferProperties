import Foundation
import SwiftInferCore

/// Cycle 120 — evidence-recording leg of `VerifyInteractionPipeline`,
/// split out of the main file so the core enum body stays under
/// SwiftLint's `type_body_length` cap (mirrors the
/// `ActionSequenceStubEmitter+Types` split). Milestone 2's batch
/// recorder (the race-free path for a parallel `--all` survey) will
/// land alongside `recordEvidence` here.
extension VerifyInteractionPipeline {

    /// Cycle 111 — best-effort upsert of one interaction-verify outcome
    /// into the shared `.swiftinfer/verify-evidence.json` store. The
    /// identity is the invariant's already-normalized hash (16-char
    /// uppercase hex, no `0x`) — the exact join key the discover-side
    /// consumer looks up via `suggestion.identity.normalized`. The
    /// parsed result's `outcome` is already a `VerifyEvidenceOutcome`,
    /// so no mapping is needed (unlike the algebraic `VerifyOutcome`).
    static func recordEvidence(
        invariant: InteractionInvariantSuggestion,
        result: InteractionVerifyOutcomeParser.Result,
        workingDirectory: URL
    ) {
        let packageRoot = findPackageRoot(startingFrom: workingDirectory) ?? workingDirectory
        let recordWarnings = VerifyEvidenceRecorder.record(
            VerifyEvidence(
                identityHash: invariant.identity.normalized,
                template: invariant.family.rawValue,
                outcome: result.outcome,
                detail: result.detail,
                capturedAt: Date(),
                swiftInferVersion: VerifyEvidenceRecorder.swiftInferVersion
            ),
            packageRoot: packageRoot
        )
        for warning in recordWarnings {
            FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
        }
    }
}
