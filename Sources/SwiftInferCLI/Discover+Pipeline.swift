import Foundation
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter

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

        /// M11.2 — equivalence-class hints keyed by the promoted
        /// suggestion's identity. Threaded through to
        /// `InteractiveTriage.Context.equivalenceClassHintsByIdentity`
        /// so the accept-flow renderer (M11.2d) can reach the hint
        /// without paying a per-suggestion storage cost on every
        /// `Suggestion` instance (the §13 row 4 memory ceiling rule).
        public let equivalenceClassHintsByIdentity: [SuggestionIdentity: EquivalenceClassHintKind]

        public init(
            suggestions: [Suggestion],
            packageRoot: URL?,
            inverseElementPairs: [InverseElementPair] = [],
            equivalenceClassHintsByIdentity: [SuggestionIdentity: EquivalenceClassHintKind] = [:]
        ) {
            self.suggestions = suggestions
            self.packageRoot = packageRoot
            self.inverseElementPairs = inverseElementPairs
            self.equivalenceClassHintsByIdentity = equivalenceClassHintsByIdentity
        }
    }

    public static func collectVisibleSuggestions(
        directory: URL,
        includePossible: Bool? = nil,
        explicitVocabularyPath: URL? = nil,
        explicitConfigPath: URL? = nil,
        explicitTestDirectory: URL? = nil,
        diagnostics: any DiagnosticOutput
    ) throws -> PipelineResult {
        let setup = resolvePipelineSetup(
            directory: directory,
            includePossible: includePossible,
            explicitVocabularyPath: explicitVocabularyPath,
            explicitConfigPath: explicitConfigPath,
            explicitTestDirectory: explicitTestDirectory,
            diagnostics: diagnostics
        )
        // TestLifter M1.5 — scan the resolved test directory for test
        // bodies, run the slicer + detectors, and convert the resulting
        // LiftedSuggestions into CrossValidationKeys to feed
        // TemplateRegistry's +20 cross-validation seam (PRD §4.1).
        // TestSuiteParser only emits summaries for files containing
        // recognized test methods, so production source naturally
        // produces no lifted records.
        let liftedArtifacts = try TestLifter.discover(
            in: setup.testDirectory,
            markerTable: effectiveMarkerTable(for: setup.vocabulary)
        )
        let artifacts = try TemplateRegistry.discoverArtifacts(
            in: directory,
            vocabulary: setup.vocabulary,
            diagnostic: { diagnostics.writeDiagnostic($0) },
            crossValidationFromTestLifter: liftedArtifacts.crossValidationKeys,
            counterSignalsFromTestLifter: liftedArtifacts.counterSignalKeys
        )
        // TestLifter M3.2 — promote LiftedSuggestions to Suggestions,
        // apply the same `GeneratorSelection` pass TemplateEngine ran
        // internally, and suppress promoted entries whose
        // crossValidationKey matches a TemplateEngine suggestion (the
        // +20 cross-validation signal already communicates the
        // corroboration; double-emitting would confuse the reader).
        // Survivors enter the visible stream with a +50 testBodyPattern
        // signal and the inferred generator (or `.todo` when type
        // recovery failed — PRD §16 #4 invariant preserved).
        let visible = combineAndFilter(
            artifacts: artifacts,
            liftedArtifacts: liftedArtifacts,
            setup: setup,
            directory: directory,
            diagnostics: diagnostics
        )
        // M11.2 — derive the per-identity hint map for the accept-flow
        // renderer alongside the lifted promotion. Pure function over
        // the same inputs; doesn't allocate per-Suggestion.
        let equivalenceClassHints = LiftedSuggestionPipeline.equivalenceClassHintMap(
            from: liftedArtifacts.equivalenceClassCandidates,
            summaries: artifacts.summaries
        )
        return PipelineResult(
            suggestions: visible,
            packageRoot: setup.packageRoot,
            inverseElementPairs: artifacts.inverseElementPairs,
            equivalenceClassHintsByIdentity: equivalenceClassHints
        )
    }

    /// Combine TE + lifted suggestions, skip-filter, counter-signal-filter,
    /// and apply the include-possible visibility cut. Extracted out of
    /// `collectVisibleSuggestions` to keep that function under SwiftLint's
    /// body-length cap (M13.3 vocabulary plumbing pushed it over).
    private static func combineAndFilter(
        artifacts: TemplateRegistry.DiscoverArtifacts,
        liftedArtifacts: TestLifter.Artifacts,
        setup: PipelineSetup,
        directory: URL,
        diagnostics: any DiagnosticOutput
    ) -> [Suggestion] {
        let promotedLifted = LiftedSuggestionPipeline.promote(
            lifted: liftedArtifacts.liftedSuggestions,
            templateEngineSuggestions: artifacts.suggestions,
            summaries: artifacts.summaries,
            typeDecls: artifacts.typeDecls,
            setupAnnotationsByOrigin: liftedArtifacts.setupAnnotationsByOrigin,
            constructionRecord: liftedArtifacts.constructionRecord,
            domainCallSitesByConsumer: liftedArtifacts.domainCallSitesByConsumer,
            equivalenceClassCandidates: liftedArtifacts.equivalenceClassCandidates
        )
        let skipFiltered = applyLiftedSkipMarkerFilter(
            to: promotedLifted,
            productionTarget: directory,
            testDirectory: setup.testDirectory,
            diagnostics: diagnostics
        )
        // M7 — filter lifted-side suggestions whose key matches a
        // counter-signal. Per M7 plan OD #1, the user's explicit
        // negative assertion is dispositive on the lifted side.
        let counterSignalKeys = liftedArtifacts.counterSignalKeys
        let filteredPromotedLifted = counterSignalKeys.isEmpty
            ? skipFiltered
            : skipFiltered.filter { !counterSignalKeys.contains($0.crossValidationKey) }
        let combined = artifacts.suggestions + filteredPromotedLifted
        return combined.filter { suggestion in
            setup.includePossible || suggestion.score.tier.isVisibleByDefault
        }
    }

    /// Bundle of resolved settings the discover pipeline pulls from
    /// `ConfigLoader` + `VocabularyLoader` + `effectiveTestDirectory`
    /// before invoking the discover passes. Extracted out of
    /// `collectVisibleSuggestions` to keep that function under
    /// SwiftLint's body-length cap.
    private struct PipelineSetup {
        let includePossible: Bool
        let vocabulary: Vocabulary
        let testDirectory: URL
        let packageRoot: URL?
    }

    /// M13.3 — vocabulary-driven marker-table extension. User-supplied
    /// `markerPairs` / `markerSets` from `.swiftinfer/vocabulary.json`
    /// are appended to `MarkerTable.curatedPairs` /
    /// `MarkerTable.curatedSets` so vocab is additive (curated defaults
    /// always apply).
    private static func effectiveMarkerTable(for vocabulary: Vocabulary) -> MarkerTable {
        MarkerTable(
            pairs: MarkerTable.curatedPairs + vocabulary.markerPairs,
            sets: MarkerTable.curatedSets + vocabulary.markerSets
        )
    }

    // swiftlint:disable:next function_parameter_count
    private static func resolvePipelineSetup(
        directory: URL,
        includePossible: Bool?,
        explicitVocabularyPath: URL?,
        explicitConfigPath: URL?,
        explicitTestDirectory: URL?,
        diagnostics: any DiagnosticOutput
    ) -> PipelineSetup {
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
        // TestLifter M6.0 — resolve the test directory separately
        // from the production target. Default walk-up looks for
        // <package-root>/Tests/; the user can override with --test-dir.
        let testDirectory = effectiveTestDirectory(
            productionTarget: directory,
            explicitTestDir: explicitTestDirectory,
            diagnostic: { diagnostics.writeDiagnostic("warning: \($0)") }
        )
        return PipelineSetup(
            includePossible: effectiveIncludePossible,
            vocabulary: vocabResult.vocabulary,
            testDirectory: testDirectory,
            packageRoot: configResult.packageRoot
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

    /// TestLifter M6.0 — resolve the directory TestLifter scans for
    /// tests with CLI > walk-up > production-target precedence.
    ///
    /// Precedence:
    /// 1. **Explicit `--test-dir <path>`** wins when the path exists
    ///    on disk. When the path doesn't exist, emit a warning and
    ///    fall through to walk-up resolution (matches the
    ///    `--vocabulary` warn-and-degrade posture).
    /// 2. **Walk-up to package root + `<root>/Tests/`** — walk parent
    ///    directories from `productionTarget` looking for
    ///    `Package.swift`, and on hit return `<root>/Tests/` if it
    ///    exists.
    /// 3. **Fallback to `productionTarget`** — current pre-M6.0
    ///    behavior (degraded but not broken). Real CLI users won't
    ///    hit this in practice; integration test fixtures that pass
    ///    a tmpdir without `Package.swift` will.
    ///
    /// Pure function over its inputs (modulo the `diagnostic`
    /// closure). Exposed at module scope so the
    /// `DiscoverCLITestDirTests` suite can exercise the resolver
    /// directly.
    public static func effectiveTestDirectory(
        productionTarget: URL,
        explicitTestDir: URL?,
        diagnostic: (String) -> Void
    ) -> URL {
        let fileManager = FileManager.default
        if let explicit = explicitTestDir {
            if fileManager.fileExists(atPath: explicit.path) {
                return explicit
            }
            diagnostic(
                "--test-dir path '\(explicit.path)' does not exist; "
                    + "falling back to walk-up resolution"
            )
        }
        if let packageRoot = findPackageRootForTestDir(startingFrom: productionTarget) {
            let tests = packageRoot.appendingPathComponent("Tests")
            if fileManager.fileExists(atPath: tests.path) {
                return tests
            }
        }
        return productionTarget
    }

}
