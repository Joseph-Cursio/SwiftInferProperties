import Foundation

// V1.143 lint pass — the survey-mode public output types, split out of
// `VerifyCommand+AllFromIndex.swift` (which had hit SwiftLint's 400-line
// file-length cap). These are the canonical Phase 2 measurement vocabulary
// (`swift-infer verify --all-from-index` JSON stream).
extension SwiftInferCommand.Verify {

    /// V1.50.B classification — one of five outcomes per pick. Matches the
    /// v1.50 plan's five categories. Encoded as a string in the JSON output
    /// for human + machine readability.
    // This CLI survey-output vocabulary intentionally mirrors Core's persistence enum
    // `VerifyEvidenceOutcome` (byte-identical raw values). They're kept as two types across the
    // CLI/Core module boundary and bridged by `VerifyEvidenceRecorder.evidenceOutcome(for:)`, a
    // rawValue round-trip pinned by `VerifyEvidenceTests`. Not drift — a deliberate, tested seam.
    // swiftprojectlint:disable:next parallel-enum-shape
    public enum SurveyOutcome: String, Codable, Sendable {
        case measuredBothPass = "measured-bothPass"
        case measuredEdgeCaseAdvisory = "measured-edgeCaseAdvisory"
        case measuredDefaultFails = "measured-defaultFails"
        case measuredError = "measured-error"
        case architecturalCoveragePending = "architectural-coverage-pending"
    }

    /// V1.50.B JSON output record — one per pick.
    public struct SurveyRecord: Codable, Sendable {
        public let identityHash: String
        public let templateName: String
        public let primaryFunctionName: String
        public let carrier: String?
        public let outcome: SurveyOutcome
        public let outcomeDetail: String?
        /// V1.143 — the first failing input + shrunk minimal, for default-fail
        /// records, so the survey batch can accumulate the replay corpus.
        /// `nil` for non-default-fail outcomes (additive optionals; legacy
        /// survey JSON decodes unchanged).
        public let counterexample: String?
        public let shrunkCounterexample: String?

        public init(
            identityHash: String,
            templateName: String,
            primaryFunctionName: String,
            carrier: String?,
            outcome: SurveyOutcome,
            outcomeDetail: String?,
            counterexample: String? = nil,
            shrunkCounterexample: String? = nil
        ) {
            self.identityHash = identityHash
            self.templateName = templateName
            self.primaryFunctionName = primaryFunctionName
            self.carrier = carrier
            self.outcome = outcome
            self.outcomeDetail = outcomeDetail
            self.counterexample = counterexample
            self.shrunkCounterexample = shrunkCounterexample
        }
    }
}
