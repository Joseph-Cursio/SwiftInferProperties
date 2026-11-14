import Foundation
@testable import SwiftInferCore
import Testing

/// #701 — a suggestion's subject fingerprint covers the law's data that lives outside every
/// body: a `documented-range` row's doc-comment bounds.
///
/// **The defect.** The bounds come from the doc comment, and neither the identity
/// (`documented-range|<signature>`) nor a body fingerprint reads it, so after editing only
/// "(0.0 to 1.0)" to "(0.0 to 0.5)" discover applied the old `measured-bothPass` (+50,
/// `Verified`) to bounds never run. The end-to-end arm, through the scanner, the index
/// projection and discover's join, is `DocumentedRangeFingerprintStalenessTests`.
@Suite("Subject fingerprint — law data outside the body")
struct SubjectFingerprintLawDataTests {

    private static let location = SourceLocation(file: "Progress.swift", line: 4, column: 5)
    private static let byLocation = ["Progress.swift:4": "AAAA"]

    private static func suggestion(template: String, match: TemplateMatch?) -> Suggestion {
        Suggestion(
            templateName: template,
            evidence: [
                Evidence(displayName: "progress", signature: "() -> Double", location: location),
            ],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 40, detail: "n")]),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(whySuggested: ["n"], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "\(template)|progress"),
            match: match
        )
    }

    private static func ranged(_ lower: String, _ upper: String, _ type: String? = "Double") -> String? {
        SubjectFingerprint.forSuggestion(
            suggestion(
                template: "documented-range",
                match: .documentedRange(DocumentedRange(lower: lower, upper: upper, resultTypeName: type))
            ),
            byLocation: byLocation
        )
    }

    @Test("same body, edited bounds → a different fingerprint")
    func editedBoundsMoveTheFingerprint() throws {
        let original = try #require(Self.ranged("0.0", "1.0"))
        #expect(original != Self.ranged("0.0", "0.5"), "an edited upper bound must show")
        #expect(original != Self.ranged("-1.0", "1.0"), "an edited lower bound must show")
        #expect(original != Self.ranged("0.0", "1.0", "Float"), "Float rounds the bounds, so the type counts")
        #expect(original != Self.ranged("0.0", "1.0", nil), "a missing type is not any type")
    }

    @Test("same body, same bounds → the same fingerprint")
    func sameBoundsKeepTheFingerprint() throws {
        let first = try #require(Self.ranged("0.0", "1.0"))
        #expect(first == Self.ranged("0.0", "1.0"))
    }

    /// The fold can never equal the body-only value, so a record stamped under the body-only
    /// rule reads as stale rather than silently matching.
    @Test("a documented-range fingerprint differs from its body-only value")
    func foldedDiffersFromBodyOnly() throws {
        let bodyOnly = SubjectFingerprint.forSuggestion(
            evidenceLocations: [Self.location], byLocation: Self.byLocation
        )
        #expect(try #require(Self.ranged("0.0", "1.0")) != bodyOnly)
    }

    @Test("an unreadable body is still nil, bounds or not")
    func missingBodyStaysNil() {
        let unreachable = SubjectFingerprint.forSuggestion(
            Self.suggestion(
                template: "documented-range",
                match: .documentedRange(DocumentedRange(lower: "0", upper: "1"))
            ),
            byLocation: [:]
        )
        #expect(unreachable == nil, "bounds alone are not a fingerprint of the subject")
    }

    /// **Every other template is byte-identical to before** — equal to the body-only helper,
    /// and to the value pinned here: `SHA256("AAAA")` truncated, which is what
    /// `combining(["AAAA"])` produced before this change. A pinned literal catches a change
    /// to the hash itself, which comparing the two helpers could not.
    @Test(
        "a suggestion with no documented range keeps its body-only fingerprint, byte for byte",
        arguments: [
            ("idempotence", nil),
            ("round-trip", nil),
            ("empty-range", nil),
            (
                "selection-subset",
                TemplateMatch.selectionSubset(
                    SelectionSubsetMatch(containerType: "ConfigTree", collectionMember: "configs", elementType: "C")
                )
            ),
        ] as [(String, TemplateMatch?)]
    )
    func otherTemplatesAreUnchanged(template: String, match: TemplateMatch?) {
        let value = SubjectFingerprint.forSuggestion(
            Self.suggestion(template: template, match: match),
            byLocation: Self.byLocation
        )
        let bodyOnly = SubjectFingerprint.forSuggestion(
            evidenceLocations: [Self.location], byLocation: Self.byLocation
        )
        #expect(value == bodyOnly)
        #expect(value == "63C1DD951FFEDF6F")
    }

    /// The entry side of the one rule: an index entry's column stays bodies-only, and what
    /// verify stamps folds the entry's own bounds in — equal to the suggestion side's value.
    @Test("an entry's evidence fingerprint folds its bounds; its column stays bodies-only")
    func entryEvidenceFingerprintFolds() throws {
        let range = DocumentedRange(lower: "0.0", upper: "1.0", resultTypeName: "Double")
        let bodyOnly = try #require(
            SubjectFingerprint.forSuggestion(evidenceLocations: [Self.location], byLocation: Self.byLocation)
        )
        let ranged = SemanticIndexEntry(
            identityHash: "0x1", templateName: "documented-range", score: 40, tier: "Likely",
            primaryFunctionName: "progress", location: "Progress.swift:4:5",
            firstSeenAt: "t", lastSeenAt: "t", documentedRange: range, subjectFingerprint: bodyOnly
        )
        #expect(ranged.subjectFingerprint == bodyOnly)
        #expect(ranged.evidenceFingerprint == Self.ranged("0.0", "1.0"))

        var plain = ranged
        plain.documentedRange = nil
        #expect(plain.evidenceFingerprint == bodyOnly, "no law data → the bodies, byte for byte")

        var unreadable = ranged
        unreadable.subjectFingerprint = nil
        #expect(unreadable.evidenceFingerprint == nil, "bounds alone are not a fingerprint")
    }
}
