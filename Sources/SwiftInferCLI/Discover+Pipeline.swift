import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// Pipeline-side helpers for `swift-infer discover`. Split out of
/// `SwiftInferCommand.swift` so the main file stays focused on the
/// `AsyncParsableCommand` surface and the `Discover` struct body
/// stays under SwiftLint's 250-line cap. Also where the M6.5
/// `--update-baseline` writeout + the M6.4 `--interactive` triage
/// dispatch + the M2 vocabulary-path precedence helper live.
extension SwiftInferCommand.Discover {

    /// Tier-filtered + config-aware suggestion collection. Shared
    /// by `Discover.run` (renderer / interactive / update-baseline)
    /// and `DriftCommand.run` (M6.5) so the two subcommands stay
    /// in lockstep — anything `discover` would surface is what
    /// `drift` diffs against the baseline.
    public struct PipelineResult {
        public let suggestions: [Suggestion]
        public let packageRoot: URL?

        /// Inverse-element witness pairs (M8.3) — feeds M8.4.a's
        /// `RefactorBridgeOrchestrator.proposals(from:inverseElementPairs:)`
        /// to surface `Group` conformance proposals when the corpus
        /// has a unary inverse function alongside a binary op +
        /// identity element on the same type. Empty for the non-
        /// interactive code paths (drift, render-only); the
        /// orchestrator only consumes them in `--interactive` mode.
        public let inverseElementPairs: [InverseElementPair]

        public init(
            suggestions: [Suggestion],
            packageRoot: URL?,
            inverseElementPairs: [InverseElementPair] = []
        ) {
            self.suggestions = suggestions
            self.packageRoot = packageRoot
            self.inverseElementPairs = inverseElementPairs
        }
    }

    public static func collectVisibleSuggestions(
        directory: URL,
        includePossible: Bool? = nil,
        explicitVocabularyPath: URL? = nil,
        explicitConfigPath: URL? = nil,
        diagnostics: any DiagnosticOutput
    ) throws -> PipelineResult {
        let configResult = ConfigLoader.load(
            startingFrom: directory,
            explicitPath: explicitConfigPath
        )
        for warning in configResult.warnings {
            diagnostics.writeDiagnostic("warning: \(warning)")
        }
        let effectiveIncludePossible =
            includePossible ?? configResult.config.includePossible
        let effectiveVocabularyPath = resolveVocabularyPath(
            cliOverride: explicitVocabularyPath,
            configValue: configResult.config.vocabularyPath,
            packageRoot: configResult.packageRoot
        )
        let vocabResult = VocabularyLoader.load(
            startingFrom: directory,
            explicitPath: effectiveVocabularyPath
        )
        for warning in vocabResult.warnings {
            diagnostics.writeDiagnostic("warning: \(warning)")
        }
        let artifacts = try TemplateRegistry.discoverArtifacts(
            in: directory,
            vocabulary: vocabResult.vocabulary,
            diagnostic: { diagnostics.writeDiagnostic($0) }
        )
        let visible = artifacts.suggestions.filter { suggestion in
            effectiveIncludePossible || suggestion.score.tier.isVisibleByDefault
        }
        return PipelineResult(
            suggestions: visible,
            packageRoot: configResult.packageRoot,
            inverseElementPairs: artifacts.inverseElementPairs
        )
    }

    /// Snapshot the current run's surface-suggestion identities to
    /// `.swiftinfer/baseline.json` (M6.5). Honors `--dry-run` by
    /// reporting the would-be path on stdout and skipping the write.
    /// The renderer still emits the normal suggestion stream after
    /// the snapshot — `--update-baseline` is additive, not a mode
    /// swap.
    static func runUpdateBaseline(
        suggestions: [Suggestion],
        packageRoot: URL,
        dryRun: Bool,
        output: any DiscoverOutput
    ) throws {
        let baseline = Baseline(
            entries: suggestions.map { suggestion in
                BaselineEntry(
                    identityHash: suggestion.identity.normalized,
                    template: suggestion.templateName,
                    scoreAtSnapshot: suggestion.score.total,
                    tier: suggestion.score.tier
                )
            }
        )
        let path = BaselineLoader.defaultPath(for: packageRoot)
        if dryRun {
            output.write("[dry-run] would write baseline to \(path.path)")
            return
        }
        try BaselineLoader.write(baseline, to: path)
        output.write("Wrote baseline to \(path.path) (\(suggestions.count) entries).")
    }

    /// Drive the M6.4 `--interactive` triage session: load the
    /// existing decisions, walk surviving suggestions through the
    /// `[A/s/n/?]` prompt loop, persist the updated decisions
    /// (unless `--dry-run`).
    static func runInteractive(
        suggestions: [Suggestion],
        packageRoot: URL,
        context: InteractiveTriage.Context
    ) throws {
        let decisionsResult = DecisionsLoader.load(startingFrom: packageRoot)
        for warning in decisionsResult.warnings {
            context.diagnostics.writeDiagnostic("warning: \(warning)")
        }
        let outcome = try InteractiveTriage.run(
            suggestions: suggestions,
            existingDecisions: decisionsResult.decisions,
            context: context
        )
        if !context.dryRun, outcome.updatedDecisions != decisionsResult.decisions {
            let path = decisionsResult.packageRoot.map(DecisionsLoader.defaultPath(for:))
                ?? DecisionsLoader.defaultPath(for: packageRoot)
            try DecisionsLoader.write(outcome.updatedDecisions, to: path)
        }
    }

    /// Resolve the vocabulary path with CLI > config > implicit-walk-up
    /// precedence. Relative paths in config are resolved against the
    /// package root the config loader walked up to; absolute paths
    /// pass through unchanged. Absoluteness is checked on the raw
    /// string — `URL(fileURLWithPath:)` would otherwise re-anchor a
    /// relative path against the current working directory before we
    /// got the chance to join it with the package root.
    static func resolveVocabularyPath(
        cliOverride: URL?,
        configValue: String?,
        packageRoot: URL?
    ) -> URL? {
        if let cliOverride {
            return cliOverride
        }
        guard let raw = configValue else {
            return nil
        }
        if raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw)
        }
        if let packageRoot {
            return packageRoot.appendingPathComponent(raw)
        }
        return URL(fileURLWithPath: raw)
    }
}
