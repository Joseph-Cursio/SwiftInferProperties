import Foundation
import SwiftInferCore

// Survey persistence, split out of `VerifyCommand+AllFromIndex.swift` to keep
// that file under SwiftLint's 400-line cap (same reason `+SurveyTypes` was
// split). `persistSurveyBatch` writes the completed survey to verify-evidence
// + the replay corpus.
extension SwiftInferCommand.Verify {

    /// Persist a completed survey: verify-evidence (one upsert per record) and
    /// the v1.143 replay corpus (accumulate the default-fail counterexamples).
    /// One batch timestamp — the survey is one logical measurement run. Both
    /// writes are best-effort; warnings surface on stderr. Internal (not
    /// private) so `runParallelSurvey` calls it across the file boundary.
    /// `now` is injected (defaulting to the wall clock) so a test can pin the
    /// stamp. Flagged by SwiftProjectLint's Non-Injected Nondeterminism rule:
    /// "`Date()` makes this code unpredictable, so a property-based test can't
    /// pin the value or reproduce a failure." That is not hypothetical here —
    /// these stamps are persisted at whole-second `.iso8601` resolution, and
    /// two records that tie on the stamp are exactly what makes the log
    /// `merge` folds non-commutative (see `MergeAlgebraPropertyTests`).
    static func persistSurveyBatch(
        _ collected: [SurveyRecord],
        packageRoot: URL,
        now: Date = Date(),
        corpusProvenance: String? = nil,
        persistEvidence: Bool = true
    ) {
        // #129 — a survey that is being COMPARED against its own baseline must be able to
        // run without rewriting it. Opting out skips the replay corpus too: both are
        // outputs of the run, and a half-persisted run is a worse artifact than none.
        guard persistEvidence else { return }
        let capturedAt = now
        let batch = collected.map { record in
            VerifyEvidence(
                identityHash: VerifyEvidenceRecorder.normalizedIdentityHash(record.identityHash),
                template: record.templateName,
                outcome: VerifyEvidenceRecorder.evidenceOutcome(for: record.outcome),
                detail: record.outcomeDetail,
                capturedAt: capturedAt,
                swiftInferVersion: VerifyEvidenceRecorder.swiftInferVersion,
                // #174 — stamped on every record, including declines: a decline is
                // also a statement about this checkout, and a stream missing it on
                // half its rows is not comparable either.
                corpusProvenance: corpusProvenance
            )
        }
        let corpusEntries: [VerifyCorpusEntry] = collected.compactMap { record in
            guard let counterexample = record.counterexample else { return nil }
            return VerifyCorpusEntry(
                identityHash: VerifyEvidenceRecorder.normalizedIdentityHash(record.identityHash),
                template: record.templateName,
                counterexample: counterexample,
                shrunkCounterexample: record.shrunkCounterexample,
                seed: seedString(for: record.identityHash),
                capturedAt: capturedAt,
                swiftInferVersion: VerifyEvidenceRecorder.swiftInferVersion
            )
        }
        var warnings = VerifyEvidenceRecorder.recordBatch(batch, packageRoot: packageRoot)
            + VerifyCorpusStore.recordBatch(corpusEntries, packageRoot: packageRoot)
        // #129 — a tracked evidence file is somebody's frozen answer key, and rewriting
        // it silently turns the next comparison into a comparison against this run.
        if let tracked = TrackedFileGuard.overwriteWarning(
            for: VerifyEvidenceStore.defaultPath(for: packageRoot)
        ) {
            warnings.append(tracked)
        }
        for warning in warnings {
            FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
        }
    }
}
