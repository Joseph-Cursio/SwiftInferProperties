import Foundation

/// The interaction-side answer to "was this verdict measured against the code
/// in front of me?" — the counterpart of `SubjectFingerprint` for
/// `InteractionInvariantSuggestion`, and the input to the staleness gate that
/// `InteractionVerifyEvidenceScoring` applies.
///
/// **Why the algebraic fingerprint could not be reused as-is.** An algebraic
/// law names one or two *functions*, and `SubjectFingerprint.byLocation` keys
/// their bodies off `FunctionSummary`. An interaction invariant names a
/// *carrier* — a reducer or an `@Observable` view model — and quantifies over
/// its whole action alphabet: `ReducerCandidate` and `ViewModelCandidate` carry
/// structure (state fields, action names, parameter types) but no body text at
/// all, so there is nothing function-shaped to hash.
///
/// **The subject is therefore the carrier's source FILE**, normalized the same
/// whitespace-only way. Two bounds follow, and both are deliberate:
///
/// - **It over-invalidates.** An edit anywhere in the file moves the value,
///   including to a type the invariant has nothing to do with, so evidence is
///   withheld more often than strictly necessary. That is the safe direction
///   and the same one the algebraic gate chose: withholding good evidence
///   under-claims, applying stale evidence over-claims.
/// - **It under-invalidates across files, which is the honest weakness.** A
///   view model's methods may live in `extension VM {}` blocks in *other*
///   files (the reason `ViewModelDiscoverer` is corpus-level and two-phase), so
///   editing an action's body elsewhere leaves this fingerprint unmoved and the
///   evidence still applying. Closing that needs the discoverer to report every
///   file that contributed to a candidate, which it does not; until then this
///   gate is strictly better than the nothing it replaces, not complete.
///
/// A structural fingerprint over the candidate's fields and action names was
/// considered and rejected: it moves when the *alphabet* changes but not when a
/// method BODY changes from correct to broken, which is exactly the edit that
/// falsifies a verified invariant.
public enum InteractionSubjectFingerprint {

    /// Fingerprint the file named by a `<path>:<line>` location.
    ///
    /// `nil` when the location does not parse or the file cannot be read — and
    /// `nil` is *withholding*, not passing: the gate treats an unknown current
    /// fingerprint as "cannot be matched", so an unreadable subject silently
    /// under-claims rather than silently promoting.
    ///
    /// `readFile` is injected so the rule can be tested without a filesystem;
    /// `InteractionVerifyEvidenceScoring` stays pure by taking the computed
    /// values rather than reaching for the disk itself.
    public static func of(
        location: String,
        readFile: (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) }
    ) -> String? {
        guard let path = filePath(fromLocation: location) else { return nil }
        guard let text = readFile(path) else { return nil }
        return SubjectFingerprint.of(bodyText: text)
    }

    /// Strip the trailing `:<line>` from a `<path>:<line>` location.
    ///
    /// Only a trailing all-digits component is removed, so a path that itself
    /// contains a colon survives, and a location with no line suffix is taken
    /// as a bare path rather than rejected.
    static func filePath(fromLocation location: String) -> String? {
        guard !location.isEmpty else { return nil }
        guard let separator = location.lastIndex(of: ":") else { return location }
        let suffix = location[location.index(after: separator)...]
        guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else { return location }
        let path = String(location[location.startIndex..<separator])
        return path.isEmpty ? nil : path
    }

    /// The per-identity map the scoring fold expects, built from the
    /// suggestions being graded. Producer and consumer both route through
    /// `of(location:)` so the two cannot drift into disagreeing about what a
    /// subject is — the failure the algebraic side paid for when scoring and
    /// rendering each decided staleness for themselves.
    public static func byIdentity(
        for suggestions: [InteractionInvariantSuggestion],
        readFile: (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) }
    ) -> [String: String] {
        var out: [String: String] = [:]
        var cache: [String: String?] = [:]
        for suggestion in suggestions {
            let location = suggestion.reducerLocation
            let fingerprint: String?
            if let cached = cache[location] {
                fingerprint = cached
            } else {
                fingerprint = of(location: location, readFile: readFile)
                cache[location] = fingerprint
            }
            if let fingerprint {
                out[suggestion.identity.normalized] = fingerprint
            }
        }
        return out
    }
}
