import Foundation
import SwiftInferCore

/// The **executed** evidence a discover run folds into its grades.
///
/// Two sources, deliberately bundled: `swift-infer verify`'s own outcomes, keyed by
/// suggestion identity, and PropertyLawKit's law verdicts, keyed by carrier. They arrived
/// separately and were threaded as separate parameters until adding the second pushed
/// `combineAndFilter` past SwiftLint's parameter cap — which was a fair signal that they are
/// one concept: *what has actually been run, as opposed to what was inferred*.
///
/// Empty is the normal state for both, and both empty means the pipeline behaves exactly as
/// it did before either existed.
public struct DiscoverEvidenceInputs: Sendable {

    /// `swift-infer verify` outcomes, keyed by `SuggestionIdentity.normalized`.
    public let verifyByIdentity: [String: VerifyEvidence]

    /// PropertyLawKit verdicts, keyed by carrier inside the log.
    public let kit: KitEvidenceLog

    /// Neither source present — the normal state, and the value that makes the pipeline
    /// behave exactly as it did before either existed.
    public static let unrun = Self()

    public init(
        verifyByIdentity: [String: VerifyEvidence] = [:],
        kit: KitEvidenceLog = KitEvidenceLog()
    ) {
        self.verifyByIdentity = verifyByIdentity
        self.kit = kit
    }
}
