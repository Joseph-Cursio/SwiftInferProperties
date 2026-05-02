import Foundation

/// Pure-function drift computation for `swift-infer drift` (M6.5).
/// Takes (current suggestions, baseline, decisions) and returns the
/// filtered list of warning candidates per PRD §9 +
/// `docs/M6 Plan.md` open decision #4 (Strong-tier-only):
///
/// 1. **Identity not in baseline** — the suggestion didn't exist (or
///    wasn't surfaced) at the last `--update-baseline` snapshot.
/// 2. **Strong-tier-only** — Likely / Possible additions are silent
///    here per PRD §9's "non-fatal warning per new Strong-tier
///    suggestion." Future `--include-likely` opt-in is M-post.
/// 3. **No recorded decision** — if the user has already
///    accepted / skipped / rejected (M6.1 `Decisions`), drift stays
///    quiet. Decision wins over baseline-state per the M6 plan
///    acceptance bar (f).
///
/// Output preserves input order — `discover` already sorts
/// deterministically per PRD §16 #1 (the same sort feeds the
/// renderer); drift inherits that ordering so the warning stream is
/// byte-stable across runs against an unchanged corpus.
public enum DriftDetector {

    public static func warnings(
        currentSuggestions: [Suggestion],
        baseline: Baseline,
        decisions: Decisions
    ) -> [DriftWarning] {
        currentSuggestions.compactMap { suggestion in
            guard suggestion.score.tier == .strong else { return nil }
            guard !baseline.contains(identityHash: suggestion.identity.normalized) else { return nil }
            guard decisions.record(for: suggestion.identity.normalized) == nil else { return nil }
            return DriftWarning(suggestion: suggestion)
        }
    }
}

/// One drift-warning row. Carries just enough to render the §9
/// CI-annotation-friendly stderr line — identity hash for the
/// `// swiftinfer: skip` workflow, displayName + location for
/// human navigation, template for grouping.
public struct DriftWarning: Sendable, Equatable {
    public let identityHash: String
    public let displayName: String
    public let template: String
    public let location: SourceLocation

    public init(
        identityHash: String,
        displayName: String,
        template: String,
        location: SourceLocation
    ) {
        self.identityHash = identityHash
        self.displayName = displayName
        self.template = template
        self.location = location
    }

    /// Build from a `Suggestion`. Picks the first evidence row's
    /// displayName + location — for round-trip pairs that's the
    /// canonical forward (sorted by file/line per the
    /// `roundTripPairing` template), so the warning anchors at the
    /// natural "first half" of the pair.
    public init(suggestion: Suggestion) {
        let evidence = suggestion.evidence.first
        self.init(
            identityHash: suggestion.identity.normalized,
            displayName: evidence?.displayName ?? "<unknown>",
            template: suggestion.templateName,
            location: evidence?.location ?? SourceLocation(file: "<unknown>", line: 0, column: 0)
        )
    }

    /// Render the §9 CI-annotation-friendly stderr line. Pinned by
    /// `DriftCommandTests` byte-stable golden so callers can rely on
    /// the format across SwiftInferProperties versions.
    public func renderedLine() -> String {
        "warning: drift: new Strong suggestion 0x\(identityHash) for "
            + "\(displayName) at \(location.file):\(location.line) — "
            + "\(template) (no recorded decision)"
    }
}
