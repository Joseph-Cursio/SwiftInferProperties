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
    static func persistSurveyBatch(_ collected: [SurveyRecord], packageRoot: URL) {
        let capturedAt = Date()
        let batch = collected.map { record in
            VerifyEvidence(
                identityHash: VerifyEvidenceRecorder.normalizedIdentityHash(record.identityHash),
                template: record.templateName,
                outcome: VerifyEvidenceRecorder.evidenceOutcome(for: record.outcome),
                detail: record.outcomeDetail,
                capturedAt: capturedAt,
                swiftInferVersion: VerifyEvidenceRecorder.swiftInferVersion
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
        let warnings = VerifyEvidenceRecorder.recordBatch(batch, packageRoot: packageRoot)
            + VerifyCorpusStore.recordBatch(corpusEntries, packageRoot: packageRoot)
        for warning in warnings {
            FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
        }
    }
}
