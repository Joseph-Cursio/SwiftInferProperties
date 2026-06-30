/// Renders the `@lint.effect pure` advisory section for `discover` output.
///
/// A deliberately separate renderer from `SuggestionRenderer`: effect
/// annotations are advice, not property-test candidates, so they get their own
/// clearly-labelled block beneath the suggestions rather than being formatted
/// as scored picks.
public enum EffectAnnotationRenderer {

    /// Returns a rendered advisory block, or the empty string when there is no
    /// advice (so callers can append unconditionally without emitting an empty
    /// header).
    public static func render(_ advice: [EffectAnnotationAdvice]) -> String {
        guard !advice.isEmpty else { return "" }

        var lines: [String] = []
        let noun = advice.count == 1 ? "function" : "functions"
        lines.append("Pure-effect annotations (\(advice.count) \(noun)):")
        lines.append(
            "  These look referentially transparent. Adding the annotation lets "
                + "the linter and PBT pipeline treat them as pure."
        )
        for item in advice {
            lines.append("")
            lines.append("  • \(item.displayName)  \(item.signature)")
            lines.append("    \(item.location.file):\(item.location.line)")
            lines.append("    add: \(item.recommendedAnnotation)")
            lines.append("    why: \(item.rationale)")
        }
        return lines.joined(separator: "\n")
    }
}
