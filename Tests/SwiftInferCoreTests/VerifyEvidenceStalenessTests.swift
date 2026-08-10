import Foundation
@testable import SwiftInferCore
import Testing

/// Verify evidence is only evidence about the code it was measured on.
///
/// **The defect these guard, measured on this repo (road test §10.2).** `SuggestionIdentity`
/// is `(template, canonical signature)` and deliberately blind to the body — it has to be,
/// because PRD §7.5 promises `// swiftinfer: skip [hash]` markers survive regeneration and
/// §16 #1 promises the hash survives signature-preserving refactors. The consequence nobody
/// had drawn is that a body-only edit which FALSIFIES the law leaves the identity unchanged,
/// so stale `measured-bothPass` evidence still attached and `discover` reported the now-false
/// law as `Verified` — the only execution-backed tier.
///
/// Rewriting `CarrierKindResolver.strippingGenericParameters` to `return name + "!"` (flatly
/// non-idempotent, signature byte-identical) still rendered `Score: 100 (Verified)`. The
/// no-evidence control on the same mutant read `50 (Likely)`, which is what proved the
/// evidence store — and not something else — was producing the false verdict.
@Suite("Verify evidence is validated against the body it was measured on")
struct VerifyEvidenceStalenessTests {

    // MARK: - The measured defect

    /// **The road-test mutation, as a unit test.** Same identity, different body: the
    /// promotion must not survive.
    @Test("a body change withholds a bothPass promotion")
    func changedBodyWithholdsPromotion() {
        let suggestion = makeSuggestion(weight: 40)
        let result = apply(
            suggestion, .measuredBothPass, measured: "OLDBODY000000000", current: "NEWBODY000000000"
        )

        #expect(result.score.total == 40, "the +50 must not be applied to a rewritten body")
        #expect(result.score.tier == .likely)
        #expect(!result.score.signals.contains { $0.kind == .verifyBothPass })
        #expect(result.score.signals.last?.kind == .verifyEvidenceStale)
    }

    /// The caveat has to name what happened, or the row silently loses evidence and the
    /// reader cannot tell a never-verified pick from a stale one.
    @Test("the withheld row says why, and names both bodies")
    func withheldRowExplainsItself() {
        let result = apply(
            makeSuggestion(weight: 40),
            .measuredBothPass,
            measured: "OLDBODY000000000",
            current: "NEWBODY000000000"
        )
        let caveats = result.explainability.whyMightBeWrong

        #expect(caveats.contains { $0.contains("NOT being applied") })
        #expect(caveats.contains { $0.contains("DIFFERENT version") })
        #expect(caveats.contains { $0.contains("OLDBODY000000000") }, "name the body measured")
        #expect(caveats.contains { $0.contains("NEWBODY000000000") }, "name the body now")
        #expect(caveats.contains { $0.contains("swift-infer verify") }, "say how to fix it")
    }

    // MARK: - The arm that must NOT fire

    /// **The control.** If this fires, the fix has switched verification off rather than
    /// validated it — a guard that withholds everything is indistinguishable from a broken
    /// evidence loop, and it would look like a clean result.
    @Test("a matching body still promotes, exactly as before")
    func matchingBodyStillPromotes() {
        let suggestion = makeSuggestion(weight: 40)
        let result = apply(
            suggestion, .measuredBothPass, measured: "SAMEBODY00000000", current: "SAMEBODY00000000"
        )

        #expect(result.score.total == 40 + VerifyEvidenceScoring.verifyBothPassWeight)
        #expect(result.score.tier == .strong)
        #expect(result.score.signals.last?.kind == .verifyBothPass)
        #expect(!result.score.signals.contains { $0.kind == .verifyEvidenceStale })
    }

    // MARK: - Symmetry: the veto is withheld too

    /// Applying the premise in one direction only would be incoherent — a stale refutation
    /// is as likely to be about deleted code as a stale pass. The suppression is withdrawn;
    /// the WARNING is not, so the reader still learns a counterexample was once found.
    @Test("a body change withholds the defaultFails veto but keeps the warning")
    func changedBodyWithholdsVeto() {
        let suggestion = makeSuggestion(weight: 90)
        let result = apply(
            suggestion, .measuredDefaultFails, measured: "OLDBODY000000000", current: "NEWBODY000000000"
        )

        #expect(!result.score.isVetoed, "a refutation of a body that no longer exists must not suppress")
        #expect(result.score.tier == .strong)
        #expect(!result.score.signals.contains { $0.kind == .verifyDisproven })
        #expect(result.explainability.whyMightBeWrong.contains { $0.contains("NOT being applied") })
    }

    // MARK: - Absent fingerprints are unvalidatable, not valid

    /// Every record written before v1.149 has no fingerprint. Trusting them would preserve
    /// the defect on exactly the population known to be stale — 349 records spread over
    /// three days in this repo's own store when the fix was written.
    @Test("evidence with no recorded fingerprint is withheld")
    func absentRecordedFingerprintIsWithheld() {
        let suggestion = makeSuggestion(weight: 40)
        let result = apply(suggestion, .measuredBothPass, measured: nil, current: "ANYBODY000000000")

        #expect(result.score.total == 40)
        #expect(result.score.signals.last?.kind == .verifyEvidenceStale)
        #expect(result.explainability.whyMightBeWrong.contains { $0.contains("before swift-infer stamped") })
    }

    /// The other direction: the evidence knows what it measured, but this run could not
    /// fingerprint the subject (a bodyless declaration, or a subject the scan missed). Also
    /// unvalidatable, and it must say which of the two it is.
    @Test("a subject this run could not fingerprint withholds evidence")
    func absentCurrentFingerprintIsWithheld() {
        let suggestion = makeSuggestion(weight: 40)
        let result = apply(suggestion, .measuredBothPass, measured: "OLDBODY000000000", current: nil)

        #expect(result.score.total == 40)
        #expect(result.score.signals.last?.kind == .verifyEvidenceStale)
        #expect(result.explainability.whyMightBeWrong.contains { $0.contains("could not fingerprint") })
    }

    // MARK: - The fingerprint itself

    /// Whitespace is normalized so reindenting a function does not invalidate its evidence;
    /// everything else is significant.
    @Test("formatting does not move the fingerprint but a real edit does")
    func fingerprintIgnoresFormattingOnly() {
        let original = SubjectFingerprint.of(bodyText: "{ return name }")
        let reindented = SubjectFingerprint.of(bodyText: "{\n    return   name\n}")
        let edited = SubjectFingerprint.of(bodyText: "{ return name + \"!\" }")

        #expect(original == reindented, "indentation is not a semantic change")
        #expect(original != edited, "the road-test mutation must move the fingerprint")
    }

    /// A law about two functions is stale if EITHER moved. A per-function fingerprint would
    /// validate a round trip against one half and let an edit to the other half through.
    @Test("a multi-subject law's fingerprint changes when either subject changes")
    func combinedFingerprintCoversEverySubject() {
        let both = SubjectFingerprint.combining(["AAAA", "BBBB"])
        #expect(both == SubjectFingerprint.combining(["BBBB", "AAAA"]), "order of evidence must not matter")
        #expect(both != SubjectFingerprint.combining(["AAAA", "CCCC"]), "a change to either half must show")
        #expect(SubjectFingerprint.combining([]) == nil, "nothing to fingerprint is not a fingerprint")
    }

    /// Missing ANY subject yields `nil` rather than a partial fingerprint — validating a
    /// two-function law against one function is the hole, not a degraded form of the fix.
    @Test("a suggestion with an unfingerprintable subject yields nil, not a partial match")
    func partialSubjectsYieldNil() {
        let first = SourceLocation(file: "A.swift", line: 1, column: 1)
        let second = SourceLocation(file: "B.swift", line: 2, column: 1)
        let partial = SubjectFingerprint.forSuggestion(
            evidenceLocations: [first, second],
            byLocation: ["A.swift:1": "AAAA"]
        )
        #expect(partial == nil)
        #expect(SubjectFingerprint.forSuggestion(evidenceLocations: [], byLocation: [:]) == nil)
    }

    // MARK: - Helpers

    private func apply(
        _ suggestion: Suggestion,
        _ outcome: VerifyEvidenceOutcome,
        measured: String?,
        current: String?
    ) -> Suggestion {
        let evidence = VerifyEvidence(
            identityHash: suggestion.identity.normalized,
            template: suggestion.templateName,
            outcome: outcome,
            detail: "trial detail",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            swiftInferVersion: "1.149.0",
            subjectFingerprint: measured
        )
        let currentMap = current.map { [suggestion.identity.normalized: $0] } ?? [:]
        return VerifyEvidenceScoring.applied(
            to: [suggestion],
            evidenceByIdentity: [suggestion.identity.normalized: evidence],
            currentFingerprintByIdentity: currentMap
        )[0]
    }

    private func makeSuggestion(weight: Int) -> Suggestion {
        Suggestion(
            templateName: "idempotence",
            evidence: [
                Evidence(
                    displayName: "strippingGenericParameters(_:)",
                    signature: "(String) -> String",
                    location: SourceLocation(file: "CarrierKindResolver.swift", line: 224, column: 1)
                )
            ],
            score: Score(signals: [
                Signal(kind: .exactNameMatch, weight: weight, detail: "stripping")
            ]),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(
                whySuggested: ["Type-symmetry signature: T -> T (+\(weight))"],
                whyMightBeWrong: []
            ),
            identity: SuggestionIdentity(canonicalInput: "idempotence|(String) -> String")
        )
    }
}

/// Rendering must not contradict scoring.
///
/// **The defect these guard shipped WITH the staleness gate and was caught by re-reading the
/// output the next day.** `SuggestionRenderer.render` computes the displayed tier as
/// `score.tier.promoted(byVerifyOutcome:)` — `.verified` is set by the surfacing pipeline, not
/// derived from the score — and it was handed the RAW evidence map. So a row whose `+50` had
/// been correctly withheld still printed `Verified`, immediately above its own caveat saying
/// the evidence was not being applied. Measured: 4 such rows on `SwiftInferCore`.
///
/// The remedy is one rule in one place: `VerifyEvidenceScoring.applicable` filters the map,
/// and every consumer inherits that decision.
@Suite("Rendering uses only the evidence scoring accepted")
struct ApplicableEvidenceTests {

    private let identity = "AABBCCDDAABBCCDD"

    private func evidence(fingerprint: String?) -> VerifyEvidence {
        VerifyEvidence(
            identityHash: identity,
            template: "idempotence",
            outcome: .measuredBothPass,
            detail: "held",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            swiftInferVersion: "1.149.0",
            subjectFingerprint: fingerprint
        )
    }

    @Test("evidence measured on a different body is filtered out")
    func staleEvidenceIsNotApplicable() {
        let result = VerifyEvidenceScoring.applicable(
            to: [],
            evidenceByIdentity: [identity: evidence(fingerprint: "OLDBODY000000000")],
            currentFingerprintByIdentity: [identity: "NEWBODY000000000"]
        )
        #expect(result.isEmpty, "a row the scorer withheld must not reach the renderer as Verified")
    }

    @Test("evidence with no fingerprint is filtered out")
    func unfingerprintedEvidenceIsNotApplicable() {
        let result = VerifyEvidenceScoring.applicable(
            to: [],
            evidenceByIdentity: [identity: evidence(fingerprint: nil)],
            currentFingerprintByIdentity: [identity: "ANYBODY000000000"]
        )
        #expect(result.isEmpty)
    }

    /// **The control.** Filtering everything would make the renderer silent about every
    /// verified law and look like a clean result.
    @Test("evidence measured on the current body survives the filter")
    func matchingEvidenceIsApplicable() {
        let result = VerifyEvidenceScoring.applicable(
            to: [],
            evidenceByIdentity: [identity: evidence(fingerprint: "SAMEBODY00000000")],
            currentFingerprintByIdentity: [identity: "SAMEBODY00000000"]
        )
        #expect(result.count == 1)
        #expect(result[identity]?.outcome == .measuredBothPass)
    }

    /// `applicable` and `applied` must agree — the whole point is that scoring and rendering
    /// cannot diverge. Asserted over both directions rather than assumed.
    @Test("a row filtered from rendering is also withheld from scoring, and vice versa")
    func filterAndScoringAgree() {
        let suggestion = Suggestion(
            templateName: "idempotence",
            evidence: [
                Evidence(
                    displayName: "normalize(_:)",
                    signature: "(String) -> String",
                    location: SourceLocation(file: "S.swift", line: 1, column: 1)
                )
            ],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 40, detail: "n")]),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(whySuggested: ["n"], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "agree")
        )
        let key = suggestion.identity.normalized
        let record = VerifyEvidence(
            identityHash: key,
            template: "idempotence",
            outcome: .measuredBothPass,
            detail: "held",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            swiftInferVersion: "1.149.0",
            subjectFingerprint: "OLDBODY000000000"
        )
        let current = [key: "NEWBODY000000000"]

        let filtered = VerifyEvidenceScoring.applicable(
            to: [suggestion], evidenceByIdentity: [key: record], currentFingerprintByIdentity: current
        )
        let scored = VerifyEvidenceScoring.applied(
            to: [suggestion], evidenceByIdentity: [key: record], currentFingerprintByIdentity: current
        )[0]

        #expect(filtered.isEmpty, "rendering must not see it")
        #expect(scored.score.total == 40, "scoring must not count it")
        #expect(scored.score.signals.last?.kind == .verifyEvidenceStale)
    }
}
