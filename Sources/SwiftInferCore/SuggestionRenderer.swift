/// Pure-Swift renderer that turns a `Suggestion` (or list of them) into
/// the two-sided text block PRD v0.3 §4.5 specifies. Output is byte-stable
/// — the caller controls the trailing newline (rendering returns no
/// terminator), and every formatting choice (alignment, bullet glyphs,
/// section ordering) is fixed so golden-file tests can pin it.
///
/// The renderer never touches the file system or the clock; the M1
/// acceptance bar (PRD §5.8(c)) requires byte-identical reproducibility
/// under fixed inputs.
public enum SuggestionRenderer {

    /// Render a single suggestion as a multi-line block. No trailing
    /// newline — callers that print to stdout should use `print(...)`,
    /// which adds one.
    public static func render(_ suggestion: Suggestion) -> String {
        var lines: [String] = []
        lines.append("[Suggestion]")
        lines.append("Template: \(suggestion.templateName)")
        lines.append("Score:    \(suggestion.score.total) (\(suggestion.score.tier.label))")
        lines.append("")
        lines.append("Why suggested:")
        if suggestion.explainability.whySuggested.isEmpty {
            lines.append("  ✓ (no signals recorded)")
        } else {
            for line in suggestion.explainability.whySuggested {
                lines.append("  ✓ \(line)")
            }
        }
        lines.append("")
        lines.append("Why this might be wrong:")
        if suggestion.explainability.whyMightBeWrong.isEmpty {
            lines.append("  ✓ no known caveats for this template")
        } else {
            for line in suggestion.explainability.whyMightBeWrong {
                lines.append("  ⚠ \(line)")
            }
        }
        lines.append("")
        lines.append(renderGeneratorLine(suggestion.generator))
        lines.append(renderSamplingLine(
            suggestion.generator,
            identity: suggestion.identity
        ))
        lines.append("Identity:  \(suggestion.identity.display)")
        lines.append("Suppress:  // swiftinfer: skip \(suggestion.identity.display)")
        return lines.joined(separator: "\n")
    }

    /// Render a list of suggestions, prefixed by a count header. Empty
    /// input renders the "0 suggestions." sentinel only.
    public static func render(_ suggestions: [Suggestion]) -> String {
        if suggestions.isEmpty {
            return "0 suggestions."
        }
        let header = "\(suggestions.count) " +
            (suggestions.count == 1 ? "suggestion." : "suggestions.")
        var blocks: [String] = [header]
        for suggestion in suggestions {
            blocks.append(render(suggestion))
        }
        return blocks.joined(separator: "\n\n")
    }

    private static func renderGeneratorLine(_ meta: GeneratorMetadata) -> String {
        switch meta.source {
        case .notYetComputed:
            return "Generator: not yet computed (M3 prerequisite)"
        case .derivedCaseIterable, .derivedRawRepresentable,
             .derivedMemberwise, .derivedCodableRoundTrip,
             .registered, .todo, .inferredFromTests:
            let confidenceFragment = meta.confidence.map { ", confidence: .\($0.rawValue)" } ?? ""
            return "Generator: .\(meta.source.rawValue)\(confidenceFragment)"
        }
    }

    /// `meta.sampling` carries the sampling outcome; `identity` feeds
    /// the M4.3 §16 #6 lifted-test-seed derivation rendered alongside.
    /// Per the M4 plan's open decision #3 default `(b)`: the `.notRun`
    /// arm renders the seed inline so the dormant state is informative
    /// rather than apologetic — the M5+ lifted test stub picks up the
    /// same seed by re-deriving from the suggestion identity.
    private static func renderSamplingLine(
        _ meta: GeneratorMetadata,
        identity: SuggestionIdentity
    ) -> String {
        switch meta.sampling {
        case .notRun:
            let seed = SamplingSeed.derive(from: identity)
            return "Sampling:  not run; lifted test seed: \(SamplingSeed.renderHex(seed))"
        case .passed(let trials):
            return "Sampling:  \(trials)/\(trials) passed"
        case .failed(let seed, let counter):
            let hex = String(seed, radix: 16, uppercase: true)
            return "Sampling:  failed (seed: 0x\(hex), counterexample: \(counter))"
        }
    }
}
