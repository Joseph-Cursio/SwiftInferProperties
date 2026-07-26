import Foundation
import SwiftInferCore

/// PROTOTYPE (Slice B3b) — closes the discover↔verify loop for convention roles.
/// After an `outputDeterminism` invariant is verified (emit → build → run →
/// parse via `OutputDeterminismVerify`), this writes a `VerifyEvidence` record
/// keyed to the suggestion's identity, so `discover-interaction`'s existing
/// `InteractionVerifyEvidenceScoring` fold promotes a `bothPass` past `.possible`
/// (outputDeterminism carries no Finding-G deferral → `.verified`) or suppresses
/// a `defaultFails`. The convention-role analog of `ViewModelVerifyEvidence`.
public enum OutputDeterminismVerifyEvidence {

    /// `now` is injected (defaulting to the wall clock) so a test can pin the
    /// stamp — SwiftProjectLint's Non-Injected Nondeterminism rule. The stamp is
    /// persisted at whole-second `.iso8601` resolution, and two records tying on
    /// it are exactly what makes the log `merge` folds non-commutative (see
    /// `MergeAlgebraPropertyTests`).
    public static func evidence(
        for suggestion: InteractionInvariantSuggestion,
        outcome: VerifyOutcome,
        now: Date = Date()
    ) -> VerifyEvidence {
        let mapped: VerifyEvidenceOutcome
        switch outcome {
        case .bothPass:
            mapped = .measuredBothPass

        case .defaultFails:
            mapped = .measuredDefaultFails

        case .edgeCaseAdvisory:
            mapped = .measuredEdgeCaseAdvisory

        case .error:
            mapped = .measuredError
        }
        return VerifyEvidence(
            identityHash: suggestion.identity.normalized,
            template: suggestion.family.rawValue,
            outcome: mapped,
            detail: "output-determinism verify (recording fake)",
            capturedAt: now,
            swiftInferVersion: VerifyEvidenceRecorder.swiftInferVersion,
            // The verifier drives the whole no-arg action alphabet; no gated
            // family applies to outputDeterminism, so coverage is full.
            excludedActionCount: 0
        )
    }

    /// Best-effort upsert into `.swiftinfer/verify-evidence.json`.
    @discardableResult
    public static func record(
        for suggestion: InteractionInvariantSuggestion,
        outcome: VerifyOutcome,
        packageRoot: URL
    ) -> [String] {
        VerifyEvidenceRecorder.record(
            evidence(for: suggestion, outcome: outcome),
            packageRoot: packageRoot
        )
    }
}
