import Foundation

/// V2.0 M10 / accept-check follow-up — pure-function drift
/// computation for `swift-infer drift-interaction`. Analog of v1's
/// `DriftDetector` but keyed on `InteractionInvariantSuggestion`.
/// Filters current suggestions per PRD §3.6 step 7 + §16 #3:
///
/// 1. **Strong-tier-only** (or Verified — v1.65 promotion rule).
///    Likely / Possible additions stay silent. PRD §16 #3: drift
///    is non-fatal, advisory signal; suppressing sub-Strong noise
///    keeps the warning stream actionable.
/// 2. **Identity not in baseline** — the suggestion didn't exist
///    (or wasn't surfaced) at the last snapshot.
/// 3. **No recorded decision** (when decisions are supplied) —
///    if the user has already accept/skip/rejected, drift stays
///    quiet. Same M6 acceptance bar (f) as v1: decision wins over
///    baseline-state. `nil` decisions argument preserves the M10.0
///    "no filter" behavior for back-compat.
///
/// Output preserves input order — `discover-interaction` sorts
/// deterministically per PRD §16 #6, so drift inherits that
/// ordering for byte-stable warning streams.
public enum InteractionDriftDetector {

    public static func warnings(
        currentSuggestions: [InteractionInvariantSuggestion],
        baseline: InteractionBaseline,
        decisions: InteractionDecisions? = nil
    ) -> [InteractionDriftWarning] {
        currentSuggestions.compactMap { suggestion in
            guard suggestion.tier == .strong || suggestion.tier == .verified else {
                return nil
            }
            guard !baseline.contains(identityHash: suggestion.identity.normalized) else {
                return nil
            }
            if let decisions,
               decisions.record(for: suggestion.identity.normalized) != nil {
                return nil
            }
            return InteractionDriftWarning(suggestion: suggestion)
        }
    }
}

/// V2.0 M10 — one drift-warning row. Carries just enough to render
/// the §3.6 / §16 #3 CI-annotation-friendly stderr line — identity
/// hash for grep, family + reducer + predicate for human navigation.
public struct InteractionDriftWarning: Sendable, Equatable {

    public let identityHash: String
    public let family: InteractionInvariantFamily
    public let reducerQualifiedName: String
    public let reducerLocation: String
    public let predicate: String

    public init(
        identityHash: String,
        family: InteractionInvariantFamily,
        reducerQualifiedName: String,
        reducerLocation: String,
        predicate: String
    ) {
        self.identityHash = identityHash
        self.family = family
        self.reducerQualifiedName = reducerQualifiedName
        self.reducerLocation = reducerLocation
        self.predicate = predicate
    }

    /// Build from a `InteractionInvariantSuggestion`. All fields
    /// project directly from the suggestion — the warning carries no
    /// additional state.
    public init(suggestion: InteractionInvariantSuggestion) {
        self.init(
            identityHash: suggestion.identity.normalized,
            family: suggestion.family,
            reducerQualifiedName: suggestion.reducerQualifiedName,
            reducerLocation: suggestion.reducerLocation,
            predicate: suggestion.predicate
        )
    }

    /// Render the CI-annotation-friendly stderr line. Byte-stable;
    /// tests pin the format.
    public func renderedLine() -> String {
        "warning: drift: new Strong \(family.rawValue) invariant 0x\(identityHash) on "
            + "\(reducerQualifiedName) at \(reducerLocation) — predicate: \(predicate)"
    }
}
