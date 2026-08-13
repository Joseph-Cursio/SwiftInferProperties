import Foundation
@testable import SwiftInferCore
import Testing

/// The staleness gate on the INTERACTION evidence path — the algebraic side's
/// §10.8 rule, applied where it was missing. Before this, a `verify-interaction`
/// verdict promoted a suggestion forever: nothing recorded which carrier the
/// verdict was measured against, so editing the reducer or view model left the
/// `.verified` tier standing on a measurement of code that no longer existed.
///
/// **The control arm is `freshEvidenceStillApplies`.** A gate that withholds
/// everything is indistinguishable from a broken evidence loop and would read as
/// a clean result — so every withholding arm here is paired with proof that the
/// matching case still promotes.
@Suite("Interaction verify evidence — the staleness gate")
struct InteractionVerifyEvidenceStalenessTests {

    // MARK: - Fixtures

    private func pick(
        family: InteractionInvariantFamily = .idempotence,
        location: String = "/tmp/Carrier.swift:12"
    ) -> InteractionInvariantSuggestion {
        InteractionInvariantSuggestion(
            identity: SuggestionIdentity(
                canonicalInput: InteractionInvariantSuggestion.identityCanonicalInput(
                    family: family,
                    reducerQualifiedName: "Carrier",
                    predicate: "count"
                )
            ),
            family: family,
            reducerQualifiedName: "Carrier",
            reducerLocation: location,
            stateTypeName: "State",
            actionTypeName: "Action",
            predicate: "applying .refresh twice equals applying it once",
            score: 40,
            tier: .likely,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func evidence(
        for suggestion: InteractionInvariantSuggestion,
        outcome: VerifyEvidenceOutcome = .measuredBothPass,
        fingerprint: String?
    ) -> [String: VerifyEvidence] {
        [
            suggestion.identity.normalized: VerifyEvidence(
                identityHash: suggestion.identity.normalized,
                template: suggestion.family.rawValue,
                outcome: outcome,
                detail: "totalRuns=100",
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                swiftInferVersion: "1.149.0",
                excludedActionCount: 0,
                subjectFingerprint: fingerprint
            )
        ]
    }

    // MARK: - The control

    @Test("evidence measured against the current carrier still promotes")
    func freshEvidenceStillApplies() {
        let subject = pick()
        let graded = InteractionVerifyEvidenceScoring.applied(
            to: [subject],
            evidenceByIdentity: evidence(for: subject, fingerprint: "abc"),
            currentFingerprintByIdentity: [subject.identity.normalized: "abc"]
        )
        #expect(graded[0].score == 90)
        #expect(graded[0].tier == .verified)
        #expect(!graded[0].whyMightBeWrong.contains { $0.contains("NOT being applied") })
    }

    // MARK: - Withholding

    @Test("evidence measured against a DIFFERENT carrier body is withheld")
    func editedSubjectWithholdsPromotion() {
        let subject = pick()
        let graded = InteractionVerifyEvidenceScoring.applied(
            to: [subject],
            evidenceByIdentity: evidence(for: subject, fingerprint: "before"),
            currentFingerprintByIdentity: [subject.identity.normalized: "after"]
        )
        #expect(graded[0].score == 40, "a withheld outcome must not move the score")
        #expect(graded[0].tier == .likely)
        #expect(graded[0].whyMightBeWrong.contains { $0.contains("DIFFERENT version") })
    }

    /// The population this closes over: every interaction record written before
    /// the gate shipped carries no fingerprint. Trusting them would preserve the
    /// defect on exactly the records most likely to be stale.
    @Test("a record with no fingerprint counts as stale, not as valid")
    func missingFingerprintCountsAsStale() {
        let subject = pick()
        let graded = InteractionVerifyEvidenceScoring.applied(
            to: [subject],
            evidenceByIdentity: evidence(for: subject, fingerprint: nil),
            currentFingerprintByIdentity: [subject.identity.normalized: "current"]
        )
        #expect(graded[0].score == 40)
        #expect(graded[0].whyMightBeWrong.contains { $0.contains("before swift-infer stamped") })
    }

    @Test("a subject this run cannot fingerprint withholds rather than promotes")
    func unfingerprintableSubjectWithholds() {
        let subject = pick()
        let graded = InteractionVerifyEvidenceScoring.applied(
            to: [subject],
            evidenceByIdentity: evidence(for: subject, fingerprint: "abc"),
            currentFingerprintByIdentity: [:]
        )
        #expect(graded[0].score == 40)
        #expect(graded[0].whyMightBeWrong.contains { $0.contains("could not fingerprint") })
    }

    /// Both directions, at weight 0. A stale refutation is as likely to be about
    /// deleted code as a stale pass, and suppressing on it would assert more than
    /// is known — so the suppression goes and the caveat stays.
    @Test("a stale refutation is withheld too, and does not suppress")
    func staleRefutationDoesNotSuppress() {
        let subject = pick()
        let graded = InteractionVerifyEvidenceScoring.applied(
            to: [subject],
            evidenceByIdentity: evidence(for: subject, outcome: .measuredDefaultFails, fingerprint: "before"),
            currentFingerprintByIdentity: [subject.identity.normalized: "after"]
        )
        #expect(graded[0].tier == .likely, "a stale refutation must not suppress")
        #expect(graded[0].whyMightBeWrong.contains { $0.contains("NOT being applied") })
    }

    @Test("a fresh refutation still suppresses")
    func freshRefutationStillSuppresses() {
        let subject = pick()
        let graded = InteractionVerifyEvidenceScoring.applied(
            to: [subject],
            evidenceByIdentity: evidence(for: subject, outcome: .measuredDefaultFails, fingerprint: "abc"),
            currentFingerprintByIdentity: [subject.identity.normalized: "abc"]
        )
        #expect(graded[0].tier == .suppressed)
    }

    // MARK: - The fingerprint itself

    @Test("the fingerprint moves when the carrier's body changes")
    func fingerprintTracksTheBody() {
        let before = InteractionSubjectFingerprint.of(location: "/x/Carrier.swift:1") { _ in
            "final class Carrier { func refresh() { count = 1 } }"
        }
        let after = InteractionSubjectFingerprint.of(location: "/x/Carrier.swift:1") { _ in
            "final class Carrier { func refresh() { count += 1 } }"
        }
        #expect(before != nil)
        #expect(before != after, "a body edit that can falsify the invariant must move the fingerprint")
    }

    /// Whitespace-only, matching the algebraic normalization: reformatting is not
    /// an edit, so it must not withhold evidence.
    @Test("reformatting alone does not move the fingerprint")
    func reformattingIsNotAnEdit() {
        let tight = InteractionSubjectFingerprint.of(location: "/x/C.swift:1") { _ in
            "final class C { func f() { x = 1 } }"
        }
        let loose = InteractionSubjectFingerprint.of(location: "/x/C.swift:1") { _ in
            "final class C {\n    func f() {\n        x = 1\n    }\n}"
        }
        #expect(tight == loose)
    }

    @Test("an unreadable subject yields nil, which the gate reads as withhold")
    func unreadableSubjectIsNil() {
        #expect(InteractionSubjectFingerprint.of(location: "/x/Gone.swift:3") { _ in nil } == nil)
    }

    @Test(
        "a <path>:<line> location resolves to the path",
        arguments: [
            ("/a/b/Carrier.swift:12", "/a/b/Carrier.swift"),
            ("/a/b/Carrier.swift", "/a/b/Carrier.swift"),
            ("/weird:dir/Carrier.swift:3", "/weird:dir/Carrier.swift")
        ]
    )
    func locationParsing(location: String, expected: String) {
        #expect(InteractionSubjectFingerprint.filePath(fromLocation: location) == expected)
    }

    /// The map the consumer builds. Two suggestions on one carrier must agree,
    /// and the file is read once — a survey grades many invariants per carrier.
    @Test("byIdentity keys every suggestion and reads each file once")
    func byIdentityCachesPerFile() {
        var reads = 0
        let one = pick(family: .idempotence)
        let two = pick(family: .cardinality)
        let map = InteractionSubjectFingerprint.byIdentity(for: [one, two]) { _ in
            reads += 1
            return "final class Carrier {}"
        }
        #expect(map.count == 2)
        #expect(map[one.identity.normalized] == map[two.identity.normalized])
        #expect(reads == 1, "the same carrier file was read twice")
    }
}
