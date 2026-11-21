import Foundation
@testable import SwiftInferCore
import Testing

/// #711 — a dedupe's evidence fingerprint folds its route in, so a verdict recorded before verify
/// knew the route reads as unvalidatable rather than applying.
///
/// **Why the body fingerprint is not enough.** The route is read from the body, so an edit moves
/// the body fingerprint already. What it cannot see is the tool changing the law it runs for an
/// unchanged body. Before #711, verify checked a dictionary-route dedupe with strict `==`
/// idempotence, which is false of correct code (hash order), and a `measured-defaultFails` from
/// that run is a false veto. After #711 it runs an order-free oracle and the count laws. A record
/// stamped body-only cannot say which it ran.
@Suite("Subject fingerprint — a dedupe's route")
struct DedupeEvidenceFingerprintTests {

    private static let location = SourceLocation(file: "Dedupe.swift", line: 3, column: 5)
    private static let byLocation = ["Dedupe.swift:3": "BBBB"]

    private static func fingerprint(_ match: TemplateMatch?) -> String? {
        SubjectFingerprint.forSuggestion(
            Suggestion(
                templateName: "idempotence",
                evidence: [Evidence(displayName: "dedupe(_:)", signature: "([Int]) -> [Int]", location: location)],
                score: Score(signals: [Signal(kind: .exactNameMatch, weight: 10, detail: "n")]),
                generator: .m1Placeholder,
                explainability: ExplainabilityBlock(whySuggested: ["n"], whyMightBeWrong: []),
                identity: SuggestionIdentity(canonicalInput: "idempotence|dedupe"),
                match: match
            ),
            byLocation: byLocation
        )
    }

    @Test("a route moves the fingerprint off its body-only value, and the two routes differ")
    func routeFolds() throws {
        let bodyOnly = try #require(Self.fingerprint(nil))
        let set = try #require(Self.fingerprint(.dedupeCount(DedupeBody(route: .set))))
        let dictionary = try #require(Self.fingerprint(.dedupeCount(DedupeBody(route: .dictionary))))
        #expect(set != bodyOnly, "a body-only record must not validate a run that knew the route")
        #expect(dictionary != bodyOnly)
        #expect(set != dictionary, "the two routes run different laws")
        #expect(set == Self.fingerprint(.dedupeCount(DedupeBody(route: .set))), "stable")
    }

    @Test("an entry stamps what discover checks: one rule on both sides")
    func entryMatchesSuggestion() throws {
        let bodyOnly = try #require(Self.fingerprint(nil))
        var entry = SemanticIndexEntry(
            identityHash: "0x1", templateName: "idempotence", score: 45, tier: "Likely",
            primaryFunctionName: "dedupe(_:)", location: "Dedupe.swift:3:5",
            firstSeenAt: "t", lastSeenAt: "t", dedupeBody: DedupeBody(route: .dictionary),
            subjectFingerprint: bodyOnly
        )
        #expect(entry.carriesLawData)
        #expect(entry.subjectFingerprint == bodyOnly, "the column stays bodies-only")
        #expect(entry.evidenceFingerprint == Self.fingerprint(.dedupeCount(DedupeBody(route: .dictionary))))
        entry.dedupeBody = nil
        #expect(!entry.carriesLawData)
        #expect(entry.evidenceFingerprint == bodyOnly, "no route → the bodies, byte for byte")
    }

    @Test("an index written before the column decodes with no route")
    func oldIndexDecodes() throws {
        let entry = SemanticIndexEntry(
            identityHash: "0x1", templateName: "idempotence", score: 45, tier: "Likely",
            primaryFunctionName: "dedupe(_:)", location: "Dedupe.swift:3:5",
            firstSeenAt: "t", lastSeenAt: "t", dedupeBody: DedupeBody(route: .set)
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any]
        )
        #expect(object["dedupeBody"] != nil)
        object.removeValue(forKey: "dedupeBody")
        let data = try JSONSerialization.data(withJSONObject: object)
        let old = try JSONDecoder().decode(SemanticIndexEntry.self, from: data)
        #expect(old.dedupeBody == nil)
    }

    /// The column follows the other law-data columns: a re-scan is authoritative for it, and it
    /// survives the encoder. Kept here rather than in `IndexProjectionParityPropertyTests`, whose
    /// struct sits at its body-length cap.
    @Test("a re-scan's route replaces the stored one, and the column round-trips")
    func mergeAndRoundTrip() throws {
        func entry(_ body: DedupeBody?) -> SemanticIndexEntry {
            SemanticIndexEntry(
                identityHash: "0x1", templateName: "idempotence", score: 45, tier: "Likely",
                primaryFunctionName: "dedupe(_:)", location: "Dedupe.swift:3:5",
                firstSeenAt: "t", lastSeenAt: "t", dedupeBody: body
            )
        }
        let stored = entry(DedupeBody(route: .set))
        let rescanned = stored.updated(from: entry(DedupeBody(route: .dictionary)))
        #expect(rescanned.dedupeBody == DedupeBody(route: .dictionary))
        #expect(stored.updated(from: entry(nil)).dedupeBody == nil, "a body the gate now refuses drops its route")
        let decoded = try JSONDecoder().decode(SemanticIndexEntry.self, from: JSONEncoder().encode(stored))
        #expect(decoded == stored)
    }
}
