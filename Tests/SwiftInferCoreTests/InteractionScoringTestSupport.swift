import Foundation
@testable import SwiftInferCore

extension InteractionVerifyEvidenceScoring {

    /// **Test shim — assumes the evidence is CURRENT, and says so.**
    ///
    /// The production `applied` requires `currentFingerprintByIdentity` on
    /// purpose: a default would let a consumer inherit the pre-gate behaviour by
    /// forgetting. The suites that predate the gate are about the *scoring*
    /// semantics (what `+50` does to a tier, how the Finding-G pin behaves), and
    /// restating a fingerprint at each of their call sites would say nothing
    /// about those rules, so this shim supplies the map the evidence itself
    /// claims — i.e. "nothing was edited since it was measured".
    ///
    /// **Do not reach for this when the subject of the test IS staleness.**
    /// `InteractionVerifyEvidenceStalenessTests` calls the real API with maps it
    /// controls; a test written against this shim can never observe a withheld
    /// outcome, because the map always matches by construction.
    static func appliedAssumingCurrent(
        to suggestions: [InteractionInvariantSuggestion],
        evidenceByIdentity: [String: VerifyEvidence]
    ) -> [InteractionInvariantSuggestion] {
        applied(
            to: suggestions,
            evidenceByIdentity: evidenceByIdentity,
            currentFingerprintByIdentity: evidenceByIdentity.compactMapValues(\.subjectFingerprint)
        )
    }
}
