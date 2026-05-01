import SwiftInferCore

/// Cross-cutting filter pass over `[Suggestion]` that resolves the
/// contradiction-detection rules from PRD v0.3 §5.6's frozen v0.2 table.
/// M3.4 wires the two contradictions reachable in v1's template surface:
///
/// - **#2 — Commutative + non-Equatable output → drop commutativity.**
///   Equality `f(a, b) == f(b, a)` is structurally untestable when the
///   return type isn't Equatable, so the suggestion gets elided rather
///   than emitted with an unenforceable caveat.
/// - **#3 — Round-trip without `T: Equatable` → drop round-trip.**
///   `g(f(t)) == t` requires comparing values of `T`; if either domain or
///   codomain along the pair classifies `.notEquatable`, the property
///   can't be sampled, so the pair gets dropped.
///
/// Contradictions #1 and #4 from the same PRD table are structurally
/// inert in M3 — neither involutive nor binary-op idempotence templates
/// ship in v1 — and land at M7 alongside the templates that would emit
/// the conflicting suggestions in the first place.
///
/// Per the M3 plan §M3.4: the detector is a *pure* function over its
/// inputs. The discover pipeline collects suggestions, builds a
/// per-suggestion `typesToCheck` map at construction time (when both the
/// summary and the resulting `Suggestion.identity` are in scope), then
/// hands both to `filter`. Suggestions whose identity isn't in the map
/// pass through untouched — idempotence, associativity, and
/// identity-element handle their own type guards at suggestion-time and
/// don't surface a §5.6 contradiction in the M3 set.
public enum ContradictionDetector {

    /// One dropped suggestion + the human-readable reason. The
    /// `reason` text is what the CLI's diagnostic stream emits to stderr
    /// per M3 plan open decision #4 (default `(b)` — stderr per drop).
    public struct Drop: Sendable, Equatable {
        public let suggestion: Suggestion
        public let reason: String

        public init(suggestion: Suggestion, reason: String) {
            self.suggestion = suggestion
            self.reason = reason
        }
    }

    /// Outcome of a `filter` call. `kept` preserves input order; `dropped`
    /// is in input order too so callers (the CLI diagnostic stream
    /// included) see drops in the same order suggestions were produced.
    public struct FilterOutcome: Sendable, Equatable {
        public let kept: [Suggestion]
        public let dropped: [Drop]

        public init(kept: [Suggestion], dropped: [Drop]) {
            self.kept = kept
            self.dropped = dropped
        }
    }

    /// Apply the §5.6 contradiction rules. A suggestion is dropped when
    /// any type text in `typesToCheck[identity]` classifies as
    /// `.notEquatable` per `resolver`. `.unknown` is treated as keep
    /// (M3 plan open decision #1 default — match the M1/M2
    /// caveat-don't-drop posture; the curated non-Equatable list is
    /// large enough to catch the obvious cases).
    public static func filter(
        _ suggestions: [Suggestion],
        typesToCheck: [SuggestionIdentity: [String]],
        resolver: EquatableResolver
    ) -> FilterOutcome {
        var kept: [Suggestion] = []
        var dropped: [Drop] = []
        for suggestion in suggestions {
            if let drop = drop(for: suggestion, typesToCheck: typesToCheck, resolver: resolver) {
                dropped.append(drop)
            } else {
                kept.append(suggestion)
            }
        }
        return FilterOutcome(kept: kept, dropped: dropped)
    }

    private static func drop(
        for suggestion: Suggestion,
        typesToCheck: [SuggestionIdentity: [String]],
        resolver: EquatableResolver
    ) -> Drop? {
        guard let types = typesToCheck[suggestion.identity] else {
            return nil
        }
        guard let offending = types.first(where: { resolver.classify(typeText: $0) == .notEquatable }) else {
            return nil
        }
        return Drop(
            suggestion: suggestion,
            reason: makeReason(suggestion: suggestion, offendingType: offending)
        )
    }

    /// Diagnostic text rendered into stderr by the CLI. Format mirrors
    /// the existing `warning: <message>` line shape from
    /// `VocabularyLoader` / `ConfigLoader` — the CLI prefixes with
    /// `contradiction: ` when forwarding so the channel is identifiable
    /// without needing a structural change to the diagnostic protocol.
    private static func makeReason(suggestion: Suggestion, offendingType: String) -> String {
        let displayName = suggestion.evidence.first?.displayName ?? "<unknown>"
        let location = suggestion.evidence.first.map { "\($0.location.file):\($0.location.line)" } ?? "<unknown>"
        return "dropped \(suggestion.templateName) suggestion for \(displayName) at \(location)"
            + " — type '\(offendingType)' is not Equatable\(prdReference(for: suggestion.templateName))"
    }

    private static func prdReference(for templateName: String) -> String {
        switch templateName {
        case "commutativity": return " (PRD §5.6 #2)"
        case "round-trip": return " (PRD §5.6 #3)"
        default: return ""
        }
    }
}
