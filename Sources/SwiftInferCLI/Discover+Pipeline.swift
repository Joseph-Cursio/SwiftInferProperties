import Foundation
import PropertyLawCore
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

        /// V1.47.C — type declarations the discover pass saw, keyed by
        /// bare type name (no generic argument list). `IndexCommand`
        /// reads this to populate `SemanticIndexEntry.typeShape` so the
        /// verify pipeline can call `DerivationStrategist.strategy(for:)`
        /// without re-parsing the user's source. Empty for code paths
        /// that don't need it (the renderer / interactive flows).
        public let typeShapesByName: [String: PropertyLawCore.TypeShape]

        public init(
            suggestions: [Suggestion],
            packageRoot: URL?,
            inverseElementPairs: [InverseElementPair] = [],
            equivalenceClassHintsByIdentity: [SuggestionIdentity: EquivalenceClassHintKind] = [:],
            consumerProducerChainHintsByIdentity: [SuggestionIdentity: DomainHint] = [:],
            typeShapesByName: [String: PropertyLawCore.TypeShape] = [:]
        ) {
            self.suggestions = suggestions
            self.packageRoot = packageRoot
            self.inverseElementPairs = inverseElementPairs
            self.equivalenceClassHintsByIdentity = equivalenceClassHintsByIdentity
            self.consumerProducerChainHintsByIdentity = consumerProducerChainHintsByIdentity
            self.typeShapesByName = typeShapesByName
        }
    }

    public static func collectVisibleSuggestions(
        directory: URL,
        includePossible: Bool? = nil,
        explicitVocabularyPath: URL? = nil,
        explicitConfigPath: URL? = nil,
        explicitTestDirectory: URL? = nil,
        packsOverride: String? = nil,
        verifyEvidenceByIdentity: [String: VerifyEvidence] = [:],
        diagnostics: any DiagnosticOutput
    ) throws -> PipelineResult {
        let setup = resolvePipelineSetup(
            directory: directory,
            includePossible: includePossible,
            overrides: ExplicitOverrides(
                vocabularyPath: explicitVocabularyPath,
                configPath: explicitConfigPath,
                testDirectory: explicitTestDirectory,
                packs: packsOverride
            ),
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
            verifyEvidenceByIdentity: verifyEvidenceByIdentity,
            diagnostics: diagnostics
        )
        let hints = buildHintsAndShapes(
            artifacts: artifacts,
            liftedArtifacts: liftedArtifacts
        )
        return PipelineResult(
            suggestions: visible,
            packageRoot: setup.packageRoot,
            inverseElementPairs: artifacts.inverseElementPairs,
            equivalenceClassHintsByIdentity: hints.equivalenceClassHints,
            consumerProducerChainHintsByIdentity: hints.chainHints,
            typeShapesByName: hints.typeShapesByName
        )
    }

    /// V1.89 lint pass — bundle for the derived per-identity maps
    /// that `collectVisibleSuggestions` folds into `PipelineResult`.
    /// Returned by `buildHintsAndShapes` as a struct rather than a
    /// 3-tuple to satisfy SwiftLint's `large_tuple` rule.
    private struct HintsAndShapes {
        let equivalenceClassHints: [SuggestionIdentity: EquivalenceClassHintKind]
        let chainHints: [SuggestionIdentity: DomainHint]
        let typeShapesByName: [String: PropertyLawCore.TypeShape]
    }

    /// V1.89 lint pass — extracted from `collectVisibleSuggestions`
    /// for SwiftLint's body-length cap. Bundles three derived
    /// per-identity maps:
    ///
    /// - M11.2 equivalence-class hints — accept-flow renderer reads
    ///   these by promoted-suggestion identity.
    /// - M16.3 consumer-producer-chain hints — same out-of-band
    ///   storage shape, keyed by promoted-suggestion identity.
    /// - V1.47.C type-shape map keyed by bare type name — feeds
    ///   `IndexCommand.populate` so verify can call `DerivationStrategist`
    ///   without re-parsing user sources.
    private static func buildHintsAndShapes(
        artifacts: TemplateRegistry.DiscoverArtifacts,
        liftedArtifacts: TestLifter.Artifacts
    ) -> HintsAndShapes {
        let equivalenceClassHints = LiftedSuggestionPipeline.equivalenceClassHintMap(
            from: liftedArtifacts.equivalenceClassCandidates,
            summaries: artifacts.summaries,
            typeDecls: artifacts.typeDecls
        )
        let chainHints = LiftedSuggestionPipeline.consumerProducerChainHintMap(
            from: liftedArtifacts.domainCallSitesByConsumer,
            roundTripPairs: LiftedSuggestionPipeline.roundTripPairs(
                from: liftedArtifacts.liftedSuggestions
            ),
            summaries: artifacts.summaries
        )
        let typeShapesByName = Dictionary(
            uniqueKeysWithValues: TypeShapeBuilder.shapes(from: artifacts.typeDecls)
                .map { ($0.name, $0) }
        )
        return HintsAndShapes(
            equivalenceClassHints: equivalenceClassHints,
            chainHints: chainHints,
            typeShapesByName: typeShapesByName
        )
    }

    /// Combine TE + lifted suggestions, skip-filter, counter-signal-filter,
    /// and apply the include-possible visibility cut. Extracted from
    /// `collectVisibleSuggestions` for SwiftLint's body-length cap.
    private static func combineAndFilter(
        artifacts: TemplateRegistry.DiscoverArtifacts,
        liftedArtifacts: TestLifter.Artifacts,
        setup: PipelineSetup,
        verifyEvidenceByIdentity: [String: VerifyEvidence],
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
            productionTarget: setup.directory,
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
        // V1.67 — fold verify evidence into the grade *before* the
        // visibility cut, so a `bothPass` outcome can lift a pick past
        // the threshold (and a `defaultFails` veto drops it). V1.66.B
        // applied this after the cut, in the CLI layer, where it could
        // only re-grade already-visible picks. An empty map (every
        // caller but `discover`) leaves `combined` untouched.
        let graded = VerifyEvidenceScoring.applied(
            to: combined,
            evidenceByIdentity: verifyEvidenceByIdentity
        )
        return graded.filter { suggestion in
            let tier = suggestion.score.tier
            // `.suppressed` is never shown — not even with
            // `--include-possible` (`Tier.suppressed` doc; `renderStats`
            // assumes it). V1.67 makes this explicit: verify-disproven
            // picks land here as `.suppressed`, and the prior
            // `includePossible || isVisibleByDefault` filter would have
            // leaked them through under `--include-possible`.
            guard tier != .suppressed else { return false }
            return setup.includePossible || tier.isVisibleByDefault
        }
    }

    /// Bundle of resolved settings the discover pipeline pulls from
    /// `ConfigLoader` + `VocabularyLoader` + `effectiveTestDirectory`.
    /// V1.89 lint pass — carries the production-target `directory`
    /// too so `combineAndFilter` stays under the 5-param cap.
    private struct PipelineSetup {
        let directory: URL
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

    /// V1.89 lint pass — bundle of the four "explicit override" inputs
    /// to `resolvePipelineSetup`, lifted from individual params so the
    /// function stays under the `function_parameter_count` cap. Each
    /// field uses the same "nil means walk up / fall back to config"
    /// semantics as the original parameters.
    private struct ExplicitOverrides {
        let vocabularyPath: URL?
        let configPath: URL?
        let testDirectory: URL?
        let packs: String?
    }

    private static func resolvePipelineSetup(
        directory: URL,
        includePossible: Bool?,
        overrides: ExplicitOverrides,
        diagnostics: any DiagnosticOutput
    ) -> PipelineSetup {
        let configResult = ConfigLoader.load(
            startingFrom: directory,
            explicitPath: overrides.configPath
        )
        for warning in configResult.warnings {
            diagnostics.writeDiagnostic("warning: \(warning)")
        }
        let effectiveIncludePossible =
            includePossible ?? configResult.config.includePossible
        let effectiveVocabularyPath = resolveVocabularyPath(
            cliOverride: overrides.vocabularyPath,
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
            explicitTestDir: overrides.testDirectory
        )            { diagnostics.writeDiagnostic("warning: \($0)") }
        // V1.32.C — Domain Template Packs (PRD §20.3). Precedence
        // CLI > config > nil (no filter; all templates run).
        let templateFilter = resolveTemplateFilter(
            cliOverride: overrides.packs,
            configValue: configResult.config.packs,
            diagnostics: diagnostics
        )
        return PipelineSetup(
            directory: directory,
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
}
