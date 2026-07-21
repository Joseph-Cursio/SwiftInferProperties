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
            swiftInferVersion: VerifyEvidenceRecorder.swiftInferVersion,
            excludedActionCount: result.excludedActionCount
        )
    }

    private static func emit(_ warnings: [String]) {
        for warning in warnings {
            FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
        }
    }

    /// Cycle 125 (Phase B, guardrail #1) + cycle 136 — two jobs:
    ///
    ///   1. **Disclosure (`.tca`-only).** For a `.tca` reducer verified via
    ///      relaxed partial exploration, fold the excluded-action disclosure
    ///      into the verdict `detail` so it rides through to the evidence
    ///      record + render. No note when nothing was excluded (full
    ///      exploration) or for non-`.tca` carriers.
    ///   2. **Coverage stamp (all carriers).** Stamp `excludedActionCount`
    ///      on every result so the discover-side fold can gate the cycle-135
    ///      Finding-G pin-overrule on *full* coverage.
    ///      `excludedCaseNames` is `0` for non-`.tca` CaseIterable reducers
    ///      and all-constructible `.tca` reducers (full coverage), and `> 0`
    ///      only for genuinely relaxed `.tca` exploration.
    static func foldPartialExplorationDisclosure(
        _ result: InteractionVerifyOutcomeParser.Result,
        candidate: ReducerCandidate
    ) -> InteractionVerifyOutcomeParser.Result {
        let excluded = ActionSequenceStubEmitter.excludedCaseNames(candidate)
        var note: String?
        if candidate.carrierKind == .tca, !excluded.isEmpty {
            let total = candidate.actionCases.count
            note = "partial exploration: explored \(total - excluded.count) of \(total) "
                + "action types (excluded: \(excluded.joined(separator: ", ")))"
        }
        let detail: String?
        if let note {
            detail = result.detail.map { "\($0) | \(note)" } ?? note
        } else {
            detail = result.detail
        }
        return InteractionVerifyOutcomeParser.Result(
            outcome: result.outcome,
            totalRuns: result.totalRuns,
            cleanRuns: result.cleanRuns,
            detail: detail,
            failingSequenceIndex: result.failingSequenceIndex,
            excludedActionCount: excluded.count
        )
    }

    /// TestStore Trace Mining (Slice 2) — append a replay-then-extend note to
    /// the verdict `detail` so the evidence record + render disclose that
    /// developer-authored orderings were checked ahead of random generation
    /// (explainability, PRD §4.5). No-op when nothing was mined
    /// (`seedTraceCount == 0`) — preserves the un-mined verdict text exactly.
    /// Preserves every other `Result` field (notably `excludedActionCount`,
    /// which the discover-side full-coverage gate reads).
    static func foldSeedTraceDisclosure(
        _ result: InteractionVerifyOutcomeParser.Result,
        seedTraceCount: Int
    ) -> InteractionVerifyOutcomeParser.Result {
        guard seedTraceCount > 0 else {
            return result
        }
        let noun = seedTraceCount == 1 ? "trace" : "traces"
        let note = "replay-then-extend: checked \(seedTraceCount) developer-authored "
            + "\(noun) before random generation"
        let detail = result.detail.map { "\($0) | \(note)" } ?? note
        return InteractionVerifyOutcomeParser.Result(
            outcome: result.outcome,
            totalRuns: result.totalRuns,
            cleanRuns: result.cleanRuns,
            detail: detail,
            failingSequenceIndex: result.failingSequenceIndex,
            excludedActionCount: result.excludedActionCount
        )
    }
}
