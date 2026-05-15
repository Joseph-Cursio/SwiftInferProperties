import Foundation
import SwiftInferCore

/// V2.0 M4.E — pure renderer turning a list of
/// `InteractionInvariantSuggestion` values into the human-readable
/// stream that `swift-infer discover-interaction` prints. Modeled on
/// v1's `SuggestionRenderer` shape (PRD §4.5 two-sided
/// "why suggested" / "why this might be wrong" blocks) with the
/// family-specific fields wired in.
///
/// **Tier filtering.** PRD §4.2 + §3.5 corollary: every new family
/// ships at default `.possible` visibility through three calibration
/// cycles. `.possible` suggestions are hidden unless
/// `includePossible: true`. The renderer emits a clear sentinel
/// when filtering would drop every suggestion — "(N possible
/// suggestions hidden — pass --include-possible)" — so the user
/// doesn't get a silent empty result while families are pending
/// calibration.
///
/// **Output is byte-stable.** No clock reads, no random seeds; the
/// only inputs are the suggestion list + the `includePossible`
/// flag. Tests pin the format.
public enum InteractionSuggestionRenderer {

    /// V2.0 M4.E — render a list of interaction suggestions.
    /// Empty list returns the "0 suggestions." sentinel. Non-empty
    /// list with everything filtered out returns the calibration-
    /// aware "N hidden, pass --include-possible" sentinel.
    public static func render(
        _ suggestions: [InteractionInvariantSuggestion],
        includePossible: Bool
    ) -> String {
        if suggestions.isEmpty {
            return "0 interaction-invariant suggestions."
        }
        let visible = filter(suggestions, includePossible: includePossible)
        if visible.isEmpty {
            let hidden = suggestions.count - visible.count
            return "0 interaction-invariant suggestions shown "
                + "(\(hidden) at .possible tier hidden — pass "
                + "--include-possible to see new-family candidates "
                + "pending calibration)."
        }
        let header = "\(visible.count) interaction-invariant "
            + (visible.count == 1 ? "suggestion." : "suggestions.")
        var blocks: [String] = [header]
        for suggestion in visible {
            blocks.append(render(suggestion))
        }
        return blocks.joined(separator: "\n\n")
    }

    /// V2.0 M4.E — render one suggestion as a multi-line block. No
    /// trailing newline — `render(_:includePossible:)` joins blocks
    /// with `"\n\n"` to keep the byte-stable shape obvious.
    public static func render(_ suggestion: InteractionInvariantSuggestion) -> String {
        var lines: [String] = []
        lines.append("[Interaction-Invariant Suggestion]")
        lines.append("Family:    \(suggestion.family.rawValue)")
        lines.append("Score:     \(suggestion.score) (\(suggestion.tier.label))")
        lines.append("Reducer:   \(suggestion.reducerQualifiedName)")
        lines.append("Location:  \(suggestion.reducerLocation)")
        lines.append("State:     \(suggestion.stateTypeName)")
        lines.append("Action:    \(suggestion.actionTypeName)")
        lines.append("Predicate: \(suggestion.predicate)")
        lines.append("")
        lines.append("Why suggested:")
        if suggestion.whySuggested.isEmpty {
            lines.append("  ✓ (no signals recorded)")
        } else {
            for line in suggestion.whySuggested {
                lines.append("  ✓ \(line)")
            }
        }
        lines.append("")
        lines.append("Why this might be wrong:")
        if suggestion.whyMightBeWrong.isEmpty {
            lines.append("  ✓ no known caveats for this family yet")
        } else {
            for line in suggestion.whyMightBeWrong {
                lines.append("  ⚠ \(line)")
            }
        }
        lines.append("")
        lines.append("Identity:  \(suggestion.identity.display)")
        return lines.joined(separator: "\n")
    }

    /// V2.0 M4.E — filter suggestions by tier. `.possible` and
    /// `.suppressed` are hidden unless `includePossible: true`;
    /// `.advisory` is always shown (v1 convention — advisory blocks
    /// don't have a runnable property and don't gate visibility).
    static func filter(
        _ suggestions: [InteractionInvariantSuggestion],
        includePossible: Bool
    ) -> [InteractionInvariantSuggestion] {
        suggestions.filter { suggestion in
            switch suggestion.tier {
            case .verified, .strong, .likely, .advisory:
                return true
            case .possible:
                return includePossible
            case .suppressed:
                return false
            }
        }
    }
}
