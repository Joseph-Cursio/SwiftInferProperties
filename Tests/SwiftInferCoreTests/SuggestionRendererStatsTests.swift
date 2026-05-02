import Testing
@testable import SwiftInferCore

@Suite("SuggestionRenderer.renderStats — --stats-only summary block (M5.4)")
struct SuggestionRendererStatsTests {

    // MARK: - Empty + sentinel

    @Test
    func emptyInputRendersZeroSuggestionsSentinel() {
        #expect(SuggestionRenderer.renderStats([]) == "0 suggestions.")
    }

    // MARK: - Singular vs. plural header

    @Test
    func singleSuggestionInSingleTemplateUsesSingularHeader() {
        let suggestion = makeSuggestion(template: "idempotence", score: 90)
        let rendered = SuggestionRenderer.renderStats([suggestion])
        #expect(rendered.hasPrefix("1 suggestion across 1 template.\n"))
    }

    @Test
    func multipleSuggestionsAcrossMultipleTemplatesUsesPluralHeader() {
        let suggestions = [
            makeSuggestion(template: "idempotence", score: 90),
            makeSuggestion(template: "round-trip", score: 70)
        ]
        let rendered = SuggestionRenderer.renderStats(suggestions)
        #expect(rendered.hasPrefix("2 suggestions across 2 templates.\n"))
    }

    // MARK: - Per-template / per-tier breakdown

    @Test
    func tierBreakdownOmitsEmptyTiers() {
        // Only Strong + Likely; no Possible — the breakdown should
        // skip the empty Possible tier entirely.
        let suggestions = [
            makeSuggestion(template: "round-trip", score: 90),
            makeSuggestion(template: "round-trip", score: 90),
            makeSuggestion(template: "round-trip", score: 60)
        ]
        let rendered = SuggestionRenderer.renderStats(suggestions)
        #expect(rendered.contains("(2 Strong, 1 Likely)"))
        #expect(!rendered.contains("0 Possible"))
    }

    @Test
    func templatesAreSortedAlphabeticallyForByteStability() {
        // Insert in non-alphabetical order; renderStats must sort.
        let suggestions = [
            makeSuggestion(template: "round-trip", score: 90),
            makeSuggestion(template: "associativity", score: 90),
            makeSuggestion(template: "commutativity", score: 90),
            makeSuggestion(template: "idempotence", score: 90)
        ]
        let rendered = SuggestionRenderer.renderStats(suggestions)
        let templateOrder = rendered.split(separator: "\n").dropFirst().map { line -> String in
            // Strip leading whitespace + colon to recover the template name.
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return String(trimmed.prefix { $0 != ":" })
        }
        #expect(templateOrder == ["associativity", "commutativity", "idempotence", "round-trip"])
    }

    // MARK: - Byte-stable golden against the PRD-shaped corpus

    @Test
    func byteStableGoldenMatchesPRDExampleShape() {
        // Mirrors the §5.8 M5 example. Score values pre-bucketed into
        // Strong (90 = ≥75) / Likely (60 = 40..<75) / Possible (30 =
        // 20..<40) so the per-tier counts match the PRD exemplar.
        //
        // Per-template arrays built in separate `let`s — a single
        // chained `+` expression of this size trips the Swift compiler's
        // type-check timeout on the GitHub-hosted CI runners (works
        // locally on Swift 6.3.1; fails on the older toolchain CI uses).
        let idempotence: [Suggestion] =
            Array(repeating: makeSuggestion(template: "idempotence", score: 90), count: 8)
            + Array(repeating: makeSuggestion(template: "idempotence", score: 60), count: 3)
            + [makeSuggestion(template: "idempotence", score: 30)]
        let roundTrip: [Suggestion] =
            Array(repeating: makeSuggestion(template: "round-trip", score: 90), count: 5)
            + Array(repeating: makeSuggestion(template: "round-trip", score: 60), count: 2)
        let commutativity: [Suggestion] =
            Array(repeating: makeSuggestion(template: "commutativity", score: 90), count: 3)
            + Array(repeating: makeSuggestion(template: "commutativity", score: 60), count: 4)
            + Array(repeating: makeSuggestion(template: "commutativity", score: 30), count: 2)
        let associativity: [Suggestion] =
            Array(repeating: makeSuggestion(template: "associativity", score: 90), count: 2)
            + Array(repeating: makeSuggestion(template: "associativity", score: 60), count: 3)
            + [makeSuggestion(template: "associativity", score: 30)]
        let identityElement: [Suggestion] =
            Array(repeating: makeSuggestion(template: "identity-element", score: 90), count: 2)
            + [makeSuggestion(template: "identity-element", score: 60)]
        let suggestions = idempotence + roundTrip + commutativity + associativity + identityElement

        let expected = """
            37 suggestions across 5 templates.
              associativity:       6 (2 Strong, 3 Likely, 1 Possible)
              commutativity:       9 (3 Strong, 4 Likely, 2 Possible)
              idempotence:        12 (8 Strong, 3 Likely, 1 Possible)
              identity-element:    3 (2 Strong, 1 Likely)
              round-trip:          7 (5 Strong, 2 Likely)
            """
        #expect(SuggestionRenderer.renderStats(suggestions) == expected)
    }

    // MARK: - Helpers

    /// Build a minimal Suggestion for stats-rendering tests. The
    /// renderStats path reads only `templateName` + `score.tier`, so
    /// generator / explainability / identity get sentinel values.
    private func makeSuggestion(template: String, score: Int) -> Suggestion {
        let signal = Signal(kind: .typeSymmetrySignature, weight: score, detail: "")
        return Suggestion(
            templateName: template,
            evidence: [],
            score: Score(signals: [signal]),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "stats-test|\(template)|\(score)")
        )
    }
}
