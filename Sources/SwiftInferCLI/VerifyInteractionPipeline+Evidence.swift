import Foundation
import SwiftInferCore

/// Cycle 120 — evidence-recording leg of `VerifyInteractionPipeline`,
/// split out of the main file so the core enum body stays under
/// SwiftLint's `type_body_length` cap (mirrors the
/// `ActionSequenceStubEmitter+Types` split).
///
/// Two write paths share one record builder (`makeEvidence`):
///   - `recordEvidence` — single upsert, the single-shot
///     `verify-interaction` / `accept-check-interaction` path (cycle 111).
///   - `recordEvidenceBatch` — one read-modify-write over many records,
///     the survey path. Decoupling recording from `runWithInvariant`'s
///     hot loop (via the `persistEvidence: false` gate) is what makes a
///     *parallel* `--all` survey race-free: concurrent verifies no longer
///     each read-modify-write the shared JSON store; the survey collects
///     every outcome and writes once after the fan-out joins (milestone 3).
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
        let warnings = VerifyEvidenceRecorder.record(
            makeEvidence(invariant: invariant, result: result),
            packageRoot: packageRoot
        )
        emit(warnings)
    }

    /// Cycle 120 — best-effort upsert of a *batch* of interaction-verify
    /// outcomes in a single read-modify-write. The survey calls this once,
    /// after collecting every identity's outcome, instead of recording
    /// per-call inside `runWithInvariant` (which it now suppresses via
    /// `persistEvidence: false`). One write means concurrent verifies in a
    /// parallel survey can't lose each other's record to an interleaved
    /// read-modify-write of the shared store.
    static func recordEvidenceBatch(
        _ outcomes: [(invariant: InteractionInvariantSuggestion,
                       result: InteractionVerifyOutcomeParser.Result)],
        workingDirectory: URL
    ) {
        guard !outcomes.isEmpty else { return }
        let packageRoot = findPackageRoot(startingFrom: workingDirectory) ?? workingDirectory
        let batch = outcomes.map { makeEvidence(invariant: $0.invariant, result: $0.result) }
        emit(VerifyEvidenceRecorder.recordBatch(batch, packageRoot: packageRoot))
    }

    /// Shared record builder — single source of truth for the persisted
    /// shape so the single + batch paths write identically.
    private static func makeEvidence(
        invariant: InteractionInvariantSuggestion,
        result: InteractionVerifyOutcomeParser.Result
    ) -> VerifyEvidence {
        VerifyEvidence(
            identityHash: invariant.identity.normalized,
            template: invariant.family.rawValue,
            outcome: result.outcome,
            detail: result.detail,
            capturedAt: Date(),
            swiftInferVersion: VerifyEvidenceRecorder.swiftInferVersion
        )
    }

    private static func emit(_ warnings: [String]) {
        for warning in warnings {
            FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
        }
    }
}
