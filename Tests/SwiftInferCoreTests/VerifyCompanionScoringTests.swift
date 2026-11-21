import Foundation
@testable import SwiftInferCore
import Testing

/// #711 — a companion law's binding failure withholds a measured pass, and never vetoes.
///
/// The primary law held, so nothing here is evidence against it. But the accepted stub checks
/// the companion too, so the row must not carry `Verified` (+50 and the label), which it would
/// otherwise earn from a test that fails.
@Suite("VerifyEvidenceScoring — companion laws")
struct VerifyCompanionScoringTests {

    private static let body = "A1B2C3D4A1B2C3D4"

    private static let suggestion = Suggestion(
        templateName: "idempotence",
        evidence: [
            Evidence(
                displayName: "dedupe(_:)",
                signature: "([Int]) -> [Int]",
                location: SourceLocation(file: "D.swift", line: 3, column: 1)
            ),
        ],
        score: Score(signals: [Signal(kind: .exactNameMatch, weight: 40, detail: "dedupe")]),
        generator: .m1Placeholder,
        explainability: ExplainabilityBlock(whySuggested: ["dedupe"], whyMightBeWrong: []),
        identity: SuggestionIdentity(canonicalInput: "idempotence|dedupe")
    )

    private static func evidence(
        _ outcome: VerifyEvidenceOutcome, _ companions: [CompanionLawOutcome]?
    ) -> [String: VerifyEvidence] {
        let record = VerifyEvidence(
            identityHash: suggestion.identity.normalized, template: "idempotence", outcome: outcome,
            detail: nil, capturedAt: Date(timeIntervalSince1970: 1_700_000_000), swiftInferVersion: "t",
            subjectFingerprint: body, companionLaws: companions
        )
        return [suggestion.identity.normalized: record]
    }

    private static let current = [suggestion.identity.normalized: body]

    private static func applied(_ evidence: [String: VerifyEvidence]) -> Suggestion {
        VerifyEvidenceScoring.applied(
            to: [suggestion], evidenceByIdentity: evidence, currentFingerprintByIdentity: current
        )[0]
    }

    @Test("a default-pass companion failure withholds +50 and Verified, with a weight-0 caveat")
    func refutationWithholds() {
        let failing = Self.evidence(
            .measuredBothPass, [CompanionLawOutcome(law: "C2", status: .failed, trial: 3)]
        )
        let result = Self.applied(failing)
        #expect(result.score.total == 40, "no +50")
        #expect(!result.score.isVetoed, "not a veto: the primary law held")
        #expect(result.score.signals.last?.kind == .verifyCompanionRefuted)
        #expect(result.score.signals.last?.weight == 0)
        #expect(result.explainability.whyMightBeWrong.contains { $0.contains("C2 FAILED at trial 3") })
        let applicable = VerifyEvidenceScoring.applicable(
            to: [Self.suggestion], evidenceByIdentity: failing, currentFingerprintByIdentity: Self.current
        )
        #expect(applicable.isEmpty, "dropped, so no renderer derives `Verified` from the outcome")
    }

    @Test("held companions, and none at all, leave the measured pass applied")
    func nonBindingCompanionsApply() {
        for companions in [[CompanionLawOutcome(law: "C1", status: .held)], nil] {
            let result = Self.applied(Self.evidence(.measuredBothPass, companions))
            #expect(result.score.total == 40 + VerifyEvidenceScoring.verifyBothPassWeight)
            #expect(result.score.signals.last?.kind == .verifyBothPass)
        }
    }

    @Test("a refuted primary law keeps its veto whatever the companions say")
    func primaryRefutationStillVetoes() {
        let result = Self.applied(Self.evidence(
            .measuredDefaultFails, [CompanionLawOutcome(law: "C1", status: .trapped)]
        ))
        #expect(result.score.isVetoed)
        #expect(result.score.signals.last?.kind == .verifyDisproven)
    }

    @Test("evidence written before the field decodes with no companions")
    func oldEvidenceDecodes() throws {
        let record = try #require(Self.evidence(.measuredBothPass, nil).values.first)
        let data = try JSONEncoder().encode(record)
        #expect(String(bytes: data, encoding: .utf8)?.contains("companionLaws") == false)
        #expect(try JSONDecoder().decode(VerifyEvidence.self, from: data).companionLaws == nil)
    }
}
