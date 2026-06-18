import Foundation
import SwiftInferCore

/// PROTOTYPE — closes the discover↔verify loop for MVVM view models. After
/// a view-model invariant is verified (emit → build → run → parse), this
/// writes a `VerifyEvidence` record keyed to the suggestion's identity, so
/// `discover-interaction`'s existing `gradedByVerifyEvidence` fold
/// (`InteractionVerifyEvidenceScoring`) promotes a `bothPass` past
/// `.possible` (idempotence → `.verified`) or suppresses a `defaultFails`
/// — the same join the reducer verify pipeline uses
/// (`VerifyInteractionPipeline.recordEvidence`). The only difference: the
/// MVVM verifier yields an algebraic `VerifyOutcome`, mapped here to a
/// `VerifyEvidenceOutcome` (reducer verify already produces the latter).
public enum ViewModelVerifyEvidence {

    public static func evidence(
        for suggestion: InteractionInvariantSuggestion,
        outcome: VerifyOutcome
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
            detail: "MVVM view-model verify",
            capturedAt: Date(),
            swiftInferVersion: VerifyEvidenceRecorder.swiftInferVersion,
            // Full action-space coverage: the verifier drives the whole
            // generatable alphabet, so the cycle-135 gated-family overrule
            // (cardinality / biconditional) applies for MVVM too.
            excludedActionCount: 0
        )
    }

    /// Best-effort upsert into `.swiftinfer/verify-evidence.json`. Returns
    /// any store warnings (mirrors `VerifyEvidenceRecorder.record`).
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
