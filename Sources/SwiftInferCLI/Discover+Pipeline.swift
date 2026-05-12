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

        /// M16.3 — consumer-producer chain hints keyed by the promoted
        /// suggestion's identity. Same §13-row-4 out-of-band carrier
        /// posture as `equivalenceClassHintsByIdentity`; the M16.3
        /// accept-flow renderer reads this map by identity to reach
        /// the `DomainHint` for the writeout.
        public let consumerProducerChainHintsByIdentity: [SuggestionIdentity: DomainHint]

        public init(
            suggestions: [Suggestion],
            packageRoot: URL?,
            inverseElementPairs: [InverseElementPair] = [],
            equivalenceClassHintsByIdentity: [SuggestionIdentity: EquivalenceClassHintKind] = [:],
            consumerProducerChainHintsByIdentity: [SuggestionIdentity: DomainHint] = [:]
        ) {
            self.suggestions = suggestions
            self.packageRoot = packageRoot
            self.inverseElementPairs = inverseElementPairs
            self.equivalenceClassHintsByIdentity = equivalenceClassHintsByIdentity
            self.consumerProducerChainHintsByIdentity = consumerProducerChainHintsByIdentity
        }
    }

    public static func collectVisibleSuggestions(
        directory: URL,
        includePossible: Bool? = nil,
        explicitVocabularyPath: URL? = nil,
        explicitConfigPath: URL? = nil,
        explicitTestDirectory: URL? = nil,
        packsOverride: String? = nil,
        diagnostics: any DiagnosticOutput
    ) throws -> PipelineResult {
        let setup = resolvePipelineSetup(
            directory: directory,
            includePossible: includePossible,
            explicitVocabularyPath: explicitVocabularyPath,
            explicitConfigPath: explicitConfigPath,
            explicitTestDirectory: explicitTestDirectory,
            packsOverride: packsOverride,
            diagnostics: diagnostics
        )
        // TestLifter M1.5 — scan tests for slices feeding the +20 cross-
        // validation seam (PRD §4.1). Production source naturally
        // produces no lifted records (no recognized test methods).
        let liftedArtifacts = try TestLifter.discover(
            in: setup.testDirectory,
            markerTable: effectiveMarkerTable(for: setup.vocabulary)
        )
        let artifacts = try TemplateRegistry.discoverArtifacts(
            in: directory,
            vocabulary: setup.vocabulary,
            diagnostic: { diagnostics.writeDiagnostic($0) },
            crossValidationFromTestLifter: liftedArtifacts.crossValidationKeys,
            counterSignalsFromTestLifter: liftedArtifacts.counterSignalKeys,
            templateFilter: setup.templateFilter
        )
        // TestLifter M3.2 — promote LiftedSuggestions, share TemplateEngine's
        // GeneratorSelection pass, suppress duplicates already covered by
        // the +20 cross-validation seam. Survivors get +50 testBodyPattern.
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
            summaries: artifacts.summaries,
            typeDecls: artifacts.typeDecls
        )
        // M16.3 — same posture: derive consumer-producer-chain hint
        // map keyed on promoted suggestion identity for the accept-
        // flow renderer to consult on accept.
        let chainHints = LiftedSuggestionPipeline.consumerProducerChainHintMap(
            from: liftedArtifacts.domainCallSitesByConsumer,
            roundTripPairs: LiftedSuggestionPipeline.roundTripPairs(
                from: liftedArtifacts.liftedSuggestions
            ),
            summaries: artifacts.summaries
        )
        return PipelineResult(
            suggestions: visible,
            packageRoot: setup.packageRoot,
            inverseElementPairs: artifacts.inverseElementPairs,
            equivalenceClassHintsByIdentity: equivalenceClassHints,
            consumerProducerChainHintsByIdentity: chainHints
        )
    }

    /// Combine TE + lifted suggestions, skip-filter, counter-signal-filter,
    /// and apply the include-possible visibility cut. Extracted from
    /// `collectVisibleSuggestions` for SwiftLint's body-length cap.
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
    /// `ConfigLoader` + `VocabularyLoader` + `effectiveTestDirectory`.
    private struct PipelineSetup {
        let includePossible: Bool
        let vocabulary: Vocabulary
        let testDirectory: URL
        let packageRoot: URL?
        /// V1.32.C — Domain Template Packs (PRD §20.3). `nil` = no
        /// filter applied (all 10 templates run; current monolithic-
        /// registry behavior). Non-nil = post-discover filter to the
        /// supplied set of `templateName` values.
        let templateFilter: Set<String>?
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
        packsOverride: String?,
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
        // V1.32.C — Domain Template Packs (PRD §20.3). Precedence
        // CLI > config > nil (no filter; all templates run).
        let templateFilter = resolveTemplateFilter(
            cliOverride: packsOverride,
            configValue: configResult.config.packs,
            diagnostics: diagnostics
        )
        return PipelineSetup(
            includePossible: effectiveIncludePossible,
            vocabulary: vocabResult.vocabulary,
            testDirectory: testDirectory,
            packageRoot: configResult.packageRoot,
            templateFilter: templateFilter
        )
    }

    /// V1.32.C — resolve the effective template-filter set from the
    /// CLI `--packs` flag, the config `[discover].packs` value, or
    /// `nil` (all templates run). Emits per-name diagnostic warnings
    /// for any unknown pack names and an empty-effective-set warning
    /// so a misconfigured pipeline doesn't silently surface zero
    /// suggestions.
    private static func resolveTemplateFilter(
        cliOverride: String?,
        configValue: String?,
        diagnostics: any DiagnosticOutput
    ) -> Set<String>? {
        let effective = cliOverride ?? configValue
        guard let effective else {
            return nil
        }
        for unknown in TemplatePack.unknownPackNames(in: effective) {
            diagnostics.writeDiagnostic(
                "warning: unknown template pack '\(unknown)' (known: "
                    + "numeric, serialization, collections, algebraic, "
                    + "concurrency) — ignoring"
            )
        }
        let packs = TemplatePack.parse(effective)
        let resolved = TemplatePack.resolve(packs)
        if resolved.isEmpty {
            diagnostics.writeDiagnostic(
                "warning: no template packs enabled after parsing '\(effective)'"
                    + " — no suggestions will surface. Did you misspell a pack name?"
            )
        }
        return resolved
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

    /// TestLifter M6.0 — resolve TestLifter's scan directory with
    /// precedence: explicit `--test-dir` (warn + fall through if path
    /// doesn't exist) > walk-up to `<package-root>/Tests/` > the
    /// production target itself (degraded fallback for tmpdir fixtures
    /// without `Package.swift`). Pure function over its inputs.
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
