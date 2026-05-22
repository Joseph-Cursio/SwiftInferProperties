import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Build a one-record verify-evidence map keyed by `identityHash`, for
/// the V1.68 effective-tier triage tests.
func makeVerifyEvidenceMap(
    identityHash: String,
    outcome: VerifyEvidenceOutcome,
    template: String = "idempotence"
) -> [String: VerifyEvidence] {
    [
        identityHash: VerifyEvidence(
            identityHash: identityHash,
            template: template,
            outcome: outcome,
            detail: nil,
            capturedAt: Date(timeIntervalSince1970: 0),
            swiftInferVersion: "test"
        )
    ]
}

/// V1.68 — `DecisionRecord.tier` records the *effective* tier: the base
/// score-derived tier promoted through `Tier.promoted(byVerifyOutcome:)`
/// using the verify evidence the `Context` now carries. Closes the
/// cycle-64 gap where triage recorded the base tier, so the `metrics`
/// tier-mix never reflected verified picks.
@Suite("InteractiveTriage — effective-tier recording (V1.68)")
struct InteractiveTriageEffectiveTierTests {

    /// A `.strong` pick (score 90) with `.measuredBothPass` evidence
    /// records as `.verified`, matching what `discover` rendered.
    @Test
    func strongPickWithBothPassEvidenceRecordsVerifiedTier() throws {
        let directory = try makeTriageFixtureDirectory(name: "verified-tier")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = makeIdempotentSuggestion(funcName: "normalize", typeName: "String")
        #expect(suggestion.score.tier == .strong)
        let result = try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: .empty,
            context: makeTriageContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["a"]),
                outputDirectory: directory,
                verifyEvidenceByIdentity: makeVerifyEvidenceMap(
                    identityHash: suggestion.identity.normalized,
                    outcome: .measuredBothPass
                )
            )
        )
        let stored = try #require(result.updatedDecisions.record(for: suggestion.identity.normalized))
        #expect(stored.tier == .verified)
        #expect(stored.decision == .accepted)
    }

    /// No verify evidence loaded → promotion is a no-op, the base
    /// score-derived tier is recorded unchanged.
    @Test
    func strongPickWithNoEvidenceRecordsBaseTier() throws {
        let directory = try makeTriageFixtureDirectory(name: "base-tier")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = makeIdempotentSuggestion(funcName: "normalize", typeName: "String")
        let result = try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: .empty,
            context: makeTriageContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["a"]),
                outputDirectory: directory
            )
        )
        let stored = try #require(result.updatedDecisions.record(for: suggestion.identity.normalized))
        #expect(stored.tier == .strong)
    }

    /// Only `.measuredBothPass` promotes — a `.strong` pick with a
    /// non-bothPass outcome records the base tier unchanged.
    @Test(arguments: [
        VerifyEvidenceOutcome.measuredEdgeCaseAdvisory,
        .measuredDefaultFails,
        .measuredError,
        .architecturalCoveragePending
    ])
    func strongPickWithNonBothPassEvidenceRecordsBaseTier(
        outcome: VerifyEvidenceOutcome
    ) throws {
        let directory = try makeTriageFixtureDirectory(name: "non-bothpass-\(outcome.rawValue)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = makeIdempotentSuggestion(funcName: "normalize", typeName: "String")
        let result = try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: .empty,
            context: makeTriageContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["a"]),
                outputDirectory: directory,
                verifyEvidenceByIdentity: makeVerifyEvidenceMap(
                    identityHash: suggestion.identity.normalized,
                    outcome: outcome
                )
            )
        )
        let stored = try #require(result.updatedDecisions.record(for: suggestion.identity.normalized))
        #expect(stored.tier == .strong)
    }

    /// The effective tier is independent of the user's choice — a
    /// rejected `.strong` pick with `.measuredBothPass` evidence still
    /// records `.verified`.
    @Test
    func effectiveTierAppliesRegardlessOfDecision() throws {
        let suggestion = makeIdempotentSuggestion(funcName: "normalize", typeName: "String")
        let result = try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: .empty,
            context: makeTriageContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["n"]),
                verifyEvidenceByIdentity: makeVerifyEvidenceMap(
                    identityHash: suggestion.identity.normalized,
                    outcome: .measuredBothPass
                )
            )
        )
        let stored = try #require(result.updatedDecisions.record(for: suggestion.identity.normalized))
        #expect(stored.decision == .rejected)
        #expect(stored.tier == .verified)
    }
}
