import Foundation

// V1.143 lint pass — the survey-mode public output types, split out of
// `VerifyCommand+AllFromIndex.swift` (which had hit SwiftLint's 400-line
// file-length cap). These are the canonical Phase 2 measurement vocabulary
// (`swift-infer verify --all-from-index` JSON stream).
extension SwiftInferCommand.Verify {

    // This CLI survey-output vocabulary intentionally mirrors Core's persistence enum
    // `VerifyEvidenceOutcome` (byte-identical raw values). They're kept as two types across the
    // CLI/Core module boundary and bridged by `VerifyEvidenceRecorder.evidenceOutcome(for:)`, a
    // rawValue round-trip pinned by `VerifyEvidenceTests`. Not drift — a deliberate, tested seam.
    // swiftprojectlint:disable:next parallel-enum-shape
    /// V1.50.B classification — one of five outcomes per pick. Matches the
    /// v1.50 plan's five categories. Encoded as a string in the JSON output
    /// for human + machine readability.
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
        /// The suggestion's tier at index time — `"Strong"`, `"Likely"`, `"Possible"`,
        /// `"Advisory"` — carried so **the stream can be read without its index**.
        ///
        /// **This is the field whose absence inverted a headline.** On 2026-08-19 the
        /// whole-corpus re-take was reported as *"178 of 538 execute, down from 139 of
        /// 281"*. 266 of those 538 are `Advisory`, which **cannot execute a law by
        /// construction**, and the earlier index held none — so the honest comparison is
        /// 178 of 272 against 139 of 279, an increase from 50% to 65%. Computing that
        /// required joining to the index the run was taken against, and that index had
        /// already been overwritten twice the same day.
        ///
        /// `fixtures/whole-corpus-survey/README.md` named the gap in its own tooling row —
        /// *"the stream carries no tier, so it must be joined in from the index"* — which
        /// is why `tier_split.py` needs a second input. It no longer does.
        ///
        /// Optional because streams frozen before 2026-08-19 do not carry it, and a
        /// consumer must be able to tell *absent* from *`Advisory`*.
        public let tier: String?
        public let outcome: SurveyOutcome
        public let outcomeDetail: String?
        /// V1.143 — the first failing input + shrunk minimal, for default-fail
        /// records, so the survey batch can accumulate the replay corpus.
        /// `nil` for non-default-fail outcomes (additive optionals; legacy
        /// survey JSON decodes unchanged).
        public let counterexample: String?
        public let shrunkCounterexample: String?

        /// The subject body this record was measured against (`SubjectFingerprint`), carried
        /// from the index entry so the persisted evidence can be validated later. `nil` for
        /// a pre-v1.149 index, which reads downstream as "cannot validate".
        public let subjectFingerprint: String?

        public init(
            identityHash: String,
            templateName: String,
            primaryFunctionName: String,
            carrier: String?,
            tier: String? = nil,
            outcome: SurveyOutcome,
            outcomeDetail: String?,
            counterexample: String? = nil,
            shrunkCounterexample: String? = nil,
            subjectFingerprint: String? = nil
        ) {
            self.identityHash = identityHash
            self.templateName = templateName
            self.primaryFunctionName = primaryFunctionName
            self.carrier = carrier
            self.tier = tier
            self.outcome = outcome
            self.outcomeDetail = outcomeDetail
            self.counterexample = counterexample
            self.shrunkCounterexample = shrunkCounterexample
            self.subjectFingerprint = subjectFingerprint
        }
    }
}
