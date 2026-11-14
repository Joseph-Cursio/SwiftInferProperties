import Foundation

/// #701 — the subject fingerprint must cover everything the measured law was built from, not
/// only the bodies its evidence names.
///
/// **The hole this closes.** A `documented-range` law's bounds come from the doc comment
/// (`TemplateMatch.documentedRange`, persisted as `SemanticIndexEntry.documentedRange` and
/// refreshed by `updated(from:)`), and neither the identity (`documented-range|<signature>`)
/// nor a body fingerprint reads the doc comment. So editing only "(0.0 to 1.0)" to
/// "(0.0 to 0.5)" left every fingerprint unchanged, `VerifyEvidenceScoring.stalenessCaveat`
/// returned `nil`, and `discover` applied the old `measured-bothPass` (+50, `Verified`) — or
/// the old veto — to bounds nobody had run. Found by an adversarial review of #701 and
/// confirmed by two skeptics.
///
/// **Where the fold applies, and where it does not.** It applies to what evidence is STAMPED
/// with and what it is CHECKED against: verify stamps `SemanticIndexEntry.evidenceFingerprint`
/// (the entry's body fingerprint folded with the entry's `documentedRange`, the bounds it ran),
/// and discover checks against `forSuggestion(_:byLocation:)` for this run
/// (`SwiftInferCommand.Discover.fingerprintsByIdentity`). Both go through `stamped(bodies:lawData:)`,
/// so they cannot drift: if the two were computed by different rules a fresh measurement would
/// read as stale forever, or a stale one as fresh.
///
/// It does NOT apply to `SemanticIndexEntry.subjectFingerprint` or
/// `SurveyRecord.subjectFingerprint`, which stay **bodies only**, as every reader of them assumes.
/// `SurveyRunDiff` reads the survey's value as a BODY fingerprint to tell "the code moved" from
/// "the tool moved"; a folded value there reported `body changed` on every `documented-range` row
/// of a `main`-vs-branch A/B over one tree, hiding the tool change the diff exists to surface.
/// The folded value rides on the survey record separately (`SurveyRecord.lawDataFingerprint`).
///
/// **Every other template's fingerprint is byte-identical to the body-only value**, so no
/// evidence recorded before this change goes stale except `documented-range`'s — and a
/// `documented-range` record stamped under the body-only rule SHOULD read as unvalidatable,
/// because it cannot say which bounds it ran. That is the same safe direction `SubjectFingerprint`
/// takes everywhere: withholding good evidence under-claims, applying stale evidence over-claims.
extension SubjectFingerprint {

    /// The fingerprint of everything `suggestion`'s law is ABOUT: the bodies its evidence names,
    /// folded with any law data that lives outside those bodies. `nil` when any body is
    /// unavailable, exactly as `forSuggestion(evidenceLocations:byLocation:)`.
    public static func forSuggestion(
        _ suggestion: Suggestion,
        byLocation: [String: String]
    ) -> String? {
        stamped(
            bodies: forSuggestion(
                evidenceLocations: suggestion.evidence.map(\.location),
                byLocation: byLocation
            ),
            lawData: suggestion.match?.documentedRangeMatch
        )
    }

    /// The one rule both sides of evidence staleness follow: `bodies` folded with the law's data
    /// outside them, `bodies` unchanged when there is none, and `nil` when `bodies` is — bounds
    /// alone are not a fingerprint of the subject.
    public static func stamped(bodies: String?, lawData range: DocumentedRange?) -> String? {
        guard let bodies else { return nil }
        guard let range else { return bodies }
        return folding(range, into: bodies)
    }

    /// Fold a doc comment's stated range into a body fingerprint. All three fields count:
    /// `resultTypeName` decides whether the stub rounds the bounds through `Float`
    /// (`DocumentedRange.checkedBounds`), so it changes the law that runs.
    ///
    /// A `nil` type is spelled distinctly from any type name, and the template name leads, so
    /// the value can never equal a body-only fingerprint by construction of the input.
    static func folding(_ range: DocumentedRange, into bodies: String) -> String {
        digest(
            [
                "documented-range",
                bodies,
                range.lower,
                range.upper,
                range.resultTypeName ?? "<no result type>",
            ].joined(separator: "|")
        )
    }
}

public extension SemanticIndexEntry {

    /// What verify stamps its evidence with: the entry's body fingerprint (`subjectFingerprint`,
    /// bodies only) folded with the bounds the entry carries — the bounds verify actually ran.
    /// Equal to `subjectFingerprint` on every row with no `documentedRange`. Computed, never
    /// stored, so the index column keeps one meaning (#701).
    var evidenceFingerprint: String? {
        SubjectFingerprint.stamped(bodies: subjectFingerprint, lawData: documentedRange)
    }
}
