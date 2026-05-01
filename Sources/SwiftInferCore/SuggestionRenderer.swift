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

    /// `--stats-only` mode (M5.4). Renders a per-template /
    /// per-tier summary block instead of the full §4.5 explainability
    /// blocks — useful for CI dashboards that want to track "did the
    /// count of Strong-tier suggestions regress this commit?" without
    /// piping through the full output.
    ///
    /// Shape (PRD v0.4 §5.8 M5 example):
    /// ```
    /// 37 suggestions across 5 templates.
    ///   idempotence:        12 (8 Strong, 3 Likely, 1 Possible)
    ///   round-trip:          7 (5 Strong, 2 Likely)
    ///   commutativity:       9 (3 Strong, 4 Likely, 2 Possible)
    /// ```
    /// Templates sorted alphabetically for byte-stability across runs
    /// (PRD §16 #6 reproducibility). Tier breakdown in Strong / Likely
    /// / Possible order; empty tiers omitted; `.suppressed` excluded
    /// because suppressed suggestions never reach the renderer at the
    /// CLI surface anyway.
    public static func renderStats(_ suggestions: [Suggestion]) -> String {
        if suggestions.isEmpty {
            return "0 suggestions."
        }
        let byTemplate = Dictionary(grouping: suggestions, by: { $0.templateName })
        let templates = byTemplate.keys.sorted()
        let header = countHeader(suggestions.count, templateCount: templates.count)
        let nameWidth = templates.map(\.count).max() ?? 0
        // Total width before " (..." section: 2 leading + name + ":" + 5-wide
        // count column. Auto-expands if any count exceeds 5 digits.
        let countColumnWidth = max(5, byTemplate.values.map { String($0.count).count }.max() ?? 1)
        let targetWidth = 2 + nameWidth + 1 + countColumnWidth
        var lines: [String] = [header]
        for template in templates {
            let group = byTemplate[template] ?? []
            lines.append(renderTemplateLine(
                template: template,
                count: group.count,
                tierBreakdown: tierBreakdown(group),
                targetWidth: targetWidth
            ))
        }
        return lines.joined(separator: "\n")
    }

    private static func countHeader(_ totalCount: Int, templateCount: Int) -> String {
        let suggestionWord = totalCount == 1 ? "suggestion" : "suggestions"
        let templateWord = templateCount == 1 ? "template" : "templates"
        return "\(totalCount) \(suggestionWord) across \(templateCount) \(templateWord)."
    }

    private static func renderTemplateLine(
        template: String,
        count: Int,
        tierBreakdown: String,
        targetWidth: Int
    ) -> String {
        let prefix = "  \(template):"
        let countStr = "\(count)"
        let padding = String(
            repeating: " ",
            count: max(1, targetWidth - prefix.count - countStr.count)
        )
        return prefix + padding + countStr + " (\(tierBreakdown))"
    }

    /// Strong / Likely / Possible in tier order; empty tiers dropped.
    /// `.suppressed` is omitted by design — those suggestions don't
    /// reach the renderer from the CLI's `discover --include-possible`
    /// path, and surfacing them in the stats line would conflict with
    /// the §4.2 "never shown" rule for suppressed.
    private static func tierBreakdown(_ suggestions: [Suggestion]) -> String {
        var counts: [Tier: Int] = [:]
        for suggestion in suggestions {
            counts[suggestion.score.tier, default: 0] += 1
        }
        let parts: [String] = [Tier.strong, .likely, .possible].compactMap { tier in
            guard let value = counts[tier], value > 0 else { return nil }
            return "\(value) \(tier.label)"
        }
        return parts.joined(separator: ", ")
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
