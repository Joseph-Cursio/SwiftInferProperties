import CryptoKit
import Foundation

/// A fingerprint of the SUBJECT CODE a piece of verify evidence was taken against.
///
/// **This is deliberately not the suggestion identity, and the distinction is the whole
/// point.** `SuggestionIdentity` answers *which suggestion is this* and is required to be
/// stable across refactors — PRD §7.5 promises that `// swiftinfer: skip [hash]` markers
/// "survive regeneration", and PRD §16 #1 that the hash "survives renames and
/// signature-preserving refactors". Decisions, baselines, drift and the deterministic
/// sampling seed are all keyed on it. Folding the body into that hash would void a user's
/// skip markers and reset their decisions every time they edited a function.
///
/// So identity stays stable and *evidence* carries this instead, answering a different
/// question: **was this measurement taken against the code that is here now?**
///
/// The failure it exists to stop was measured on this repo (road test §10.2). Because the
/// identity hash is `(template, canonical signature)`, a body-only edit that FALSIFIES the
/// law leaves the identity unchanged, so a stale `measured-bothPass` still attached and
/// `discover` reported the now-false law as `Verified` — the only execution-backed tier,
/// the one a reader is entitled to trust more than a static score. Rewriting
/// `strippingGenericParameters` to `return name + "!"` (flatly non-idempotent, signature
/// byte-identical) still rendered `Score: 100 (Verified)`; the no-evidence control on the
/// same mutant read `50 (Likely)`.
///
/// ## Deliberately sensitive
///
/// Normalization collapses whitespace runs and nothing else. Comments are **kept**, and a
/// reformatting or comment edit therefore invalidates the evidence and asks for a re-verify.
/// That is over-invalidation, and it is the safe direction on purpose:
///
/// - withholding good evidence UNDER-claims — the row falls back to its static tier, which
///   is a true statement about what has been measured;
/// - applying stale evidence OVER-claims — the row asserts `Verified` about code nobody ran
///   it against, which is the defect this type exists to close.
///
/// Keeping comments is not merely caution either: this project reads comments as evidence
/// (`DocstringPropertyCorroborator` proposes laws from docstrings), so a comment is not
/// reliably inert here.
public enum SubjectFingerprint {

    /// Fingerprint one function body from its source text.
    ///
    /// Whitespace runs collapse to a single space so that indentation and line-wrapping do
    /// not move the value; everything else is significant.
    public static func of(bodyText: String) -> String {
        digest(normalized(bodyText))
    }

    /// Fingerprint a law whose subject is SEVERAL functions (a round trip names two, a
    /// differential pair names two implementations).
    ///
    /// Sorted before hashing so the value does not depend on the order evidence happens to
    /// be listed in, and **any** member changing moves the result — evidence about a pair is
    /// stale if either half was edited, which is the case a per-function fingerprint would
    /// miss.
    public static func combining(_ fingerprints: [String]) -> String? {
        guard !fingerprints.isEmpty else { return nil }
        return digest(fingerprints.sorted().joined(separator: "|"))
    }

    /// Index the scanned summaries by `"file:line"` — the same key
    /// `SemanticIndexEntry.location` uses, and the join `Suggestion.Evidence.location`
    /// answers, so a suggestion can be matched back to the functions it is about.
    public static func byLocation(_ summaries: [FunctionSummary]) -> [String: String] {
        var result: [String: String] = [:]
        for summary in summaries {
            guard let fingerprint = summary.bodyFingerprint else { continue }
            result[locationKey(summary.location)] = fingerprint
        }
        return result
    }

    /// The fingerprint of everything a suggestion is ABOUT, or `nil` if any subject's
    /// fingerprint is unavailable.
    ///
    /// **`nil` when any piece is missing, deliberately.** A partial fingerprint would
    /// validate a two-function law against one of its functions, so an edit to the other
    /// half would silently keep the evidence alive — precisely the hole being closed. It is
    /// better to decline to validate than to validate incompletely.
    public static func forSuggestion(
        evidenceLocations: [SourceLocation],
        byLocation: [String: String]
    ) -> String? {
        guard !evidenceLocations.isEmpty else { return nil }
        var found: [String] = []
        for location in evidenceLocations {
            guard let fingerprint = byLocation[locationKey(location)] else { return nil }
            found.append(fingerprint)
        }
        return combining(found)
    }

    static func locationKey(_ location: SourceLocation) -> String {
        "\(location.file):\(location.line)"
    }

    /// Collapse every run of whitespace to one space, and trim the ends.
    static func normalized(_ text: String) -> String {
        text.split { $0.isWhitespace }.joined(separator: " ")
    }

    /// `SHA256` truncated to 8 bytes, rendered as 16 uppercase hex characters — the same
    /// budget and rendering `SuggestionIdentity` uses, so the two read alike in a store.
    private static func digest(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        let hex = hashed.prefix(8).map { byte in
            let raw = String(byte, radix: 16, uppercase: true)
            return raw.count == 1 ? "0" + raw : raw
        }
        return hex.joined()
    }
}
