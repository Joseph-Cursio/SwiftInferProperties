import Foundation
import SwiftInferCore

/// V1.64.B — bridges the verify command's two entry points (single
/// `--suggestion` and `--all-from-index` survey) into the
/// `VerifyEvidenceStore`.
///
/// Evidence persistence is **best-effort**: a write failure surfaces as
/// a warning, never failing the verify command. The verify verdict is
/// the primary output; the `.swiftinfer/verify-evidence.json` side file
/// is a convenience for the v1.64 `discover` annotation consumer.
enum VerifyEvidenceRecorder {

    /// swift-infer version stamped onto written evidence — single source
    /// of truth, tracks `SwiftInferCommand.configuration.version` so the
    /// evidence reflects the binary that produced it.
    static var swiftInferVersion: String {
        SwiftInferCommand.configuration.version
    }

    /// Normalize a raw identity-hash string to the canonical persisted
    /// form — `SuggestionIdentity.normalized`: 16-char uppercase hex,
    /// no `0x` prefix. `SemanticIndexEntry.identityHash` carries the
    /// `0x`-prefixed `display` form, but `DecisionRecord` (and so this
    /// store, for cross-`.swiftinfer/`-file join consistency) keys on
    /// the stripped form. Without this the `discover` evidence-lookup
    /// would miss every pick.
    static func normalizedIdentityHash(_ raw: String) -> String {
        if raw.hasPrefix("0x") || raw.hasPrefix("0X") {
            return String(raw.dropFirst(2)).uppercased()
        }
        return raw.uppercased()
    }

    /// Map a parsed single-suggestion `VerifyOutcome` to the persisted
    /// five-category `VerifyEvidenceOutcome` + detail string. Mirrors
    /// the survey's `surveyRecord(from:context:)` outcome mapping so the
    /// two entry points write identically-shaped evidence.
    static func evidence(
        for parsed: VerifyOutcome
    ) -> (outcome: VerifyEvidenceOutcome, detail: String?) {
        switch parsed {
        case let .bothPass(defaultTrials, edgeTrials, edgeSampled):
            return (
                .measuredBothPass,
                "defaultTrials=\(defaultTrials) edgeTrials=\(edgeTrials) edgeSampled=\(edgeSampled)"
            )

        case .edgeCaseAdvisory:
            return (.measuredEdgeCaseAdvisory, nil)

        case let .defaultFails(trial, _, _, _):
            return (.measuredDefaultFails, "trial=\(trial)")

        case let .error(reason):
            return (.measuredError, "parse-error: \(reason)")
        }
    }

    /// Map a survey `SurveyOutcome` to the persisted
    /// `VerifyEvidenceOutcome`. The raw values are byte-identical
    /// (pinned by `VerifyEvidenceTests`), so this is a total rawValue
    /// round-trip; the `?? .measuredError` is unreachable defence.
    static func evidenceOutcome(
        for survey: SwiftInferCommand.Verify.SurveyOutcome
    ) -> VerifyEvidenceOutcome {
        VerifyEvidenceOutcome(rawValue: survey.rawValue) ?? .measuredError
    }

    /// Upsert one record into the store at `packageRoot`. Best-effort:
    /// read warnings and any write failure are returned for the caller
    /// to surface on stderr; the verify command never fails on a
    /// persistence error.
    static func record(
        _ evidence: VerifyEvidence,
        packageRoot: URL
    ) -> [String] {
        let existing = VerifyEvidenceStore.load(startingFrom: packageRoot)
        var warnings = existing.warnings
        let path = VerifyEvidenceStore.defaultPath(for: packageRoot)
        do {
            try VerifyEvidenceStore.write(existing.log.upserting(evidence), to: path)
        } catch {
            warnings.append(
                "could not write verify-evidence to \(path.path): \(error.localizedDescription)"
            )
        }
        return warnings
    }

    /// Upsert a batch of records into the store at `packageRoot` (survey
    /// mode). Upsert-per-record rather than wholesale overwrite so a
    /// `--template`-filtered survey leaves untouched picks' prior
    /// evidence in place. Best-effort, same posture as `record`.
    static func recordBatch(
        _ batch: [VerifyEvidence],
        packageRoot: URL
    ) -> [String] {
        guard !batch.isEmpty else { return [] }
        let existing = VerifyEvidenceStore.load(startingFrom: packageRoot)
        var warnings = existing.warnings
        var log = existing.log
        for evidence in batch {
            log = log.upserting(evidence)
        }
        let path = VerifyEvidenceStore.defaultPath(for: packageRoot)
        do {
            try VerifyEvidenceStore.write(log, to: path)
        } catch {
            warnings.append(
                "could not write verify-evidence to \(path.path): \(error.localizedDescription)"
            )
        }
        return warnings
    }
}
