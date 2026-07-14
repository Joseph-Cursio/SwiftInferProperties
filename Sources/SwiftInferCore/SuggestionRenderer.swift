/// Pure-Swift renderer that turns a `Suggestion` (or list of them) into
/// the two-sided text block PRD §4.5 specifies. Output is byte-stable
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
    ///
    /// `verifyEvidence` (V1.64.C) is the persisted `swift-infer verify`
    /// outcome for this suggestion, if any. When present it adds a
    /// `Verify:` line below `Sampling:`; when `nil` the block is
    /// byte-identical to the pre-v1.64 output, so existing goldens are
    /// unaffected.
    public static func render(
        _ suggestion: Suggestion,
        verifyEvidence: VerifyEvidence? = nil
    ) -> String {
        var lines: [String] = []
        // V1.65 — the rendered tier is the *effective* tier: a `.strong`
        // suggestion with `.measuredBothPass` verify evidence promotes to
        // `.verified`. Score total is unchanged; only the label moves.
        let effectiveTier = suggestion.score.tier
            .promoted(byVerifyOutcome: verifyEvidence?.outcome)
        lines.append("[Suggestion]")
        lines.append("Template: \(suggestion.templateName)")
        lines.append("Score:    \(suggestion.score.total) (\(effectiveTier.label))")
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
        lines.append(contentsOf: renderGeneratorRecipes(suggestion.generatorRecipes))
        lines.append(renderGeneratorLine(suggestion.generator))
        lines.append(renderSamplingLine(
            suggestion.generator,
            identity: suggestion.identity
        ))
        if let verifyEvidence {
            lines.append(renderVerifyLine(verifyEvidence))
        }
        lines.append("Identity:  \(suggestion.identity.display)")
        lines.append("Suppress:  // swiftinfer: skip \(suggestion.identity.display)")
        return lines.joined(separator: "\n")
    }

    /// Render a list of suggestions, prefixed by a count header. Empty
    /// input renders the "0 suggestions." sentinel only.
    ///
    /// `verifyEvidenceByIdentity` (V1.64.C) maps
    /// `SuggestionIdentity.normalized` → persisted verify evidence; each
    /// block is annotated with its match, if any. An empty map (the
    /// default) leaves every block byte-identical to the pre-v1.64
    /// output.
    ///
    /// **V1.65.B — verified-first ordering.** Suggestions whose effective
    /// tier promotes to `.verified` (`.strong` base + `.measuredBothPass`
    /// evidence) are floated to the top of the stream. The partition is
    /// stable — relative order within the verified group and within the
    /// rest is preserved — so the stream stays a deterministic function
    /// of (sources, vocabulary, config, verify-evidence). An empty
    /// evidence map promotes nothing, so input order is unchanged.
    public static func render(
        _ suggestions: [Suggestion],
        verifyEvidenceByIdentity: [String: VerifyEvidence] = [:]
    ) -> String {
        if suggestions.isEmpty {
            return "0 suggestions."
        }
        let header = "\(suggestions.count) " +
            (suggestions.count == 1 ? "suggestion." : "suggestions.")
        let ordered = verifiedFirst(
            suggestions,
            verifyEvidenceByIdentity: verifyEvidenceByIdentity
        )
        var blocks: [String] = [header]
        for suggestion in ordered {
            blocks.append(render(
                suggestion,
                verifyEvidence: verifyEvidenceByIdentity[suggestion.identity.normalized]
            ))
        }
        return blocks.joined(separator: "\n\n")
    }

    /// V1.65.B — stable partition that floats `.verified`-tier
    /// suggestions ahead of the rest. Pure and order-deterministic;
    /// exposed `internal` so unit tests can pin the ordering directly.
    static func verifiedFirst(
        _ suggestions: [Suggestion],
        verifyEvidenceByIdentity: [String: VerifyEvidence]
    ) -> [Suggestion] {
        var verified: [Suggestion] = []
        var rest: [Suggestion] = []
        for suggestion in suggestions {
            let effectiveTier = suggestion.score.tier.promoted(
                byVerifyOutcome: verifyEvidenceByIdentity[suggestion.identity.normalized]?.outcome
            )
            if effectiveTier == .verified {
                verified.append(suggestion)
            } else {
                rest.append(suggestion)
            }
        }
        return verified + rest
    }

    /// `--stats-only` mode (M5.4). Renders a per-template /
    /// per-tier summary block instead of the full §4.5 explainability
    /// blocks — useful for CI dashboards that want to track "did the
    /// count of Strong-tier suggestions regress this commit?" without
    /// piping through the full output.
    ///
    /// Shape (PRD §5.8 M5 example):
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
        let byTemplate = Dictionary(grouping: suggestions) { $0.templateName }
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
        let parts: [String] = [Tier.strong, .likely, .possible, .advisory].compactMap { tier in
            guard let value = counts[tier], value > 0 else { return nil }
            return "\(value) \(tier.label)"
        }
        return parts.joined(separator: ", ")
    }

    /// The generators the law needs, written out so the reader can paste and run them.
    ///
    /// Rendered **above** the `Generator:` metadata line and not folded into the caveats, because a
    /// caveat is something you read and a generator is something you *use* — and the whole reason
    /// this block exists is that three readers read the caveat and then had to write this code
    /// themselves. Each recipe carries its rationale inline: a reader who does not know why the
    /// alphabet is small will widen it on the first cleanup pass, and the law will go quiet without
    /// anyone noticing it stopped testing anything.
    static func renderGeneratorRecipes(_ recipes: [GeneratorRecipe]) -> [String] {
        guard !recipes.isEmpty else { return [] }

        var lines = ["", "Generators the law needs (a uniform one will pass VACUOUSLY):"]
        for recipe in recipes {
            lines.append("")
            lines.append("  // \(recipe.subject): \(recipe.typeName) — \(recipe.rationale)")
            for line in recipe.expression.split(separator: "\n", omittingEmptySubsequences: false) {
                lines.append("  \(line)")
            }
        }
        return lines
    }

    private static func renderGeneratorLine(_ meta: GeneratorMetadata) -> String {
        switch meta.source {
        case .notYetComputed:
            return "Generator: not yet computed (M3 prerequisite)"

        case .derivedCaseIterable, .derivedRawRepresentable,
             .derivedMemberwise, .derivedInitializer, .derivedEnumCases,
             .derivedCodableRoundTrip,
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

        case let .failed(seed, counter):
            let hex = String(seed, radix: 16, uppercase: true)
            return "Sampling:  failed (seed: 0x\(hex), counterexample: \(counter))"
        }
    }

    /// V1.64.C — render the persisted `swift-infer verify` outcome as a
    /// `Verify:` line. Only invoked when evidence exists for the
    /// suggestion; an unverified suggestion renders no line at all
    /// (most suggestions are unverified, and a "not verified" line
    /// would be noise). Glyphs mirror the rest of the block (`✓` / `⚠`)
    /// and `VerifyResultRenderer` (`✗` / `!`); `·` marks the
    /// not-yet-measurable architectural-coverage-pending state.
    private static func renderVerifyLine(_ evidence: VerifyEvidence) -> String {
        let glyph: String
        let label: String
        switch evidence.outcome {
        case .measuredBothPass:
            glyph = "✓"
            label = "bothPass"

        case .measuredEdgeCaseAdvisory:
            glyph = "⚠"
            label = "edge-case advisory"

        case .measuredDefaultFails:
            glyph = "✗"
            label = "defaultFails (verify-disproven)"

        case .measuredError:
            glyph = "!"
            label = "error"

        case .architecturalCoveragePending:
            glyph = "·"
            label = "architectural-coverage-pending"
        }
        let detailFragment = evidence.detail.map { " — \($0)" } ?? ""
        return "Verify:    \(glyph) \(label)\(detailFragment)"
    }
}
