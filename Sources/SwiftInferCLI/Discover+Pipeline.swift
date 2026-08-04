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

    public static func collectVisibleSuggestions(
        directory: URL,
        includePossible: Bool? = nil,
        docstringAdvice: Bool? = nil,
        explicitVocabularyPath: URL? = nil,
        explicitConfigPath: URL? = nil,
        explicitTestDirectory: URL? = nil,
        packsOverride: String? = nil,
        evidence: DiscoverEvidenceInputs = .unrun,
        seedManifest: SeedManifest? = nil,
        requireCorroboration: Bool = false,
        resolveEffects: Bool = false,
        diagnostics: any DiagnosticOutput
    ) throws -> PipelineResult {
        // A run over an empty corpus must not be mistaken for a run that found nothing in your
        // code. Only the empty case speaks: stderr is byte-stable here, and a per-run line naming
        // an absolute path would differ from machine to machine.
        TargetDirectory.warnIfEmpty(directory, to: diagnostics)

        let setup = resolvePipelineSetup(
            directory: directory,
            includePossible: includePossible,
            docstringAdvice: docstringAdvice,
            requireCorroboration: requireCorroboration,
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
            templateFilter: setup.templateFilter,
            rescuedRestrictedSymbols: rescuableRestrictedKeys(from: seedManifest),
            resolveEffects: resolveEffects
        )
        // TestLifter M3.2 — promote LiftedSuggestions, share TemplateEngine's
        // GeneratorSelection pass, suppress duplicates already covered by
        // the +20 cross-validation seam. Survivors get +50 testBodyPattern.
        let cut = combineAndFilter(
            artifacts: artifacts,
            liftedArtifacts: liftedArtifacts,
            setup: setup,
            evidence: evidence,
            diagnostics: diagnostics
        )
        return makePipelineResult(
            setup: setup,
            artifacts: artifacts,
            liftedArtifacts: liftedArtifacts,
            cut: cut,
            hints: buildHintsAndShapes(artifacts: artifacts, liftedArtifacts: liftedArtifacts)
        )
    }

    // Internal rather than `private`: `makePipelineResult` moved to
    // `Discover+PipelineAssembly.swift` and calls this.
    /// Mock-synthesize a generator for every distinct type the tests
    /// construct (≥ the synthesizer's site-count threshold) — broader than
    /// the per-suggestion `mockGenerator`, which only covers types that also
    /// surfaced a property suggestion.
    static func synthesizeMockGenerators(
        from record: ConstructionRecord
    ) -> [String: MockGenerator] {
        var result: [String: MockGenerator] = [:]
        for typeName in Set(record.entries.map(\.typeName)) {
            if let mock = MockGeneratorSynthesizer.synthesize(typeName: typeName, record: record) {
                result[typeName] = mock
            }
        }
        return result
    }

    // Internal rather than `private`: `makePipelineResult` moved to
    // `Discover+PipelineAssembly.swift` and names this in its signature.
    /// V1.89 lint pass — bundle for the derived per-identity maps
    /// that `collectVisibleSuggestions` folds into `PipelineResult`.
    /// Returned by `buildHintsAndShapes` as a struct rather than a
    /// 3-tuple to satisfy SwiftLint's `large_tuple` rule.
    struct HintsAndShapes {
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
    static func buildHintsAndShapes(
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
        evidence: DiscoverEvidenceInputs,
        diagnostics: any DiagnosticOutput
    ) -> VisibilityCut {
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
        // Collapse rows that are the same law about the same function before anything
        // downstream counts them. `crossValidationKey` suppression above catches the
        // TE-vs-lifted overlap; this catches copies whose identity is equal outright —
        // five golden tests asserting one law rendered as five Strong findings. See
        // `dedupedByIdentity`.
        let combined = dedupedByIdentity(artifacts.suggestions + filteredPromotedLifted)
        // V1.67 — fold verify evidence into the grade *before* the
        // visibility cut, so a `bothPass` outcome can lift a pick past
        // the threshold (and a `defaultFails` veto drops it). V1.66.B
        // applied this after the cut, in the CLI layer, where it could
        // only re-grade already-visible picks. An empty map (every
        // caller but `discover`) leaves `combined` untouched.
        let verifyGraded = VerifyEvidenceScoring.applied(
            to: combined,
            evidenceByIdentity: evidence.verifyByIdentity
        )
        // Then PropertyLawKit's verdicts. Order is deliberate — the kit's demotion applies
        // to whatever verify concluded, because a pick verify lifted to `bothPass` is still
        // unusable if the `==` it was compared with has been measured broken. An empty log
        // (the normal state) leaves this untouched. See `KitEvidenceScoring`.
        let graded = KitEvidenceScoring.applied(to: verifyGraded, evidence: evidence.kit)
        // Before the cut, not from the caller's post-cut set: the demotion is what removes
        // these from view, so reporting on survivors would guarantee silence in exactly the
        // case worth reporting. The suggestion loses visibility; the diagnosis must not.
        let coverage = emitEvidenceDiagnostics(
            graded: graded, artifacts: artifacts, evidence: evidence, diagnostics: diagnostics
        )
        // `.suppressed` is never shown — not even with `--include-possible`
        // (`Tier.suppressed` doc; `renderStats` assumes it). V1.67 makes this
        // explicit: verify-disproven picks land here as `.suppressed`, and the
        // prior `includePossible || isVisibleByDefault` filter would have
        // leaked them through under `--include-possible`.
        //
        // A suppressed pick is a law we **checked and refuted**, not one we failed to
        // show, so it is excluded from `hiddenRefutable` as well: the final answer
        // guard must never resurrect it.
        let live = graded.filter { $0.score.tier != .suppressed }
        // #8 — refutability, not the tier cut, decides visibility for a law the code
        // OWES. A refutable, role-entailed law (`isWorthSurfacingBelowCut`) surfaces
        // on a DEFAULT run even at `.possible`, the same principle the seeded path
        // already applies via `keepRoleEntailedLaws`. This does NOT leak conjectures
        // (`monotonicity`/`idempotence`/`round-trip`) — those are refutable but not
        // role-entailed, so a correct-but-honestly-named function could fail them.
        // PROTOTYPE — `--require-corroboration` withdraws default visibility from a
        // single-signal suggestion. The role-entailed escape hatch below is deliberately NOT
        // gated by it: `isWorthSurfacingBelowCut` surfaces a law the code OWES, which is a
        // different justification from "one signal fired" and does not need a second channel.
        let visible = live.filter {
            setup.includePossible
                || ($0.score.tier.isVisibleByDefault
                    && (!setup.requireCorroboration || CorroborationRule.isCorroborated($0.score)))
                || Refutability.isWorthSurfacingBelowCut($0)
        }
        .sorted(by: Self.strongestFirst)
        let visibleIdentities = Set(visible.map(\.identity))

        return VisibilityCut(
            visible: visible,
            hiddenRefutable: live.filter { candidate in
                Refutability.isRefutable(candidate) && !visibleIdentities.contains(candidate.identity)
            },
            coverage: coverage
        )
    }

    /// The tier cut's verdict, plus what it hid that could have failed.
    ///
    /// The hidden laws are carried rather than dropped because **this stage cannot tell whether
    /// hiding them is honest.** On its own, a run with nothing above the confidence bar should
    /// print "0 suggestions" and let the reader ask for `--include-possible` — that is the tier
    /// cut working. But `--seeds` synthesizes determinism laws *downstream of here*, and those
    /// turn the same run into a confident "6 suggestions", every one of them a tautology, with
    /// the only refutable law in the bin. Whether this cut told the truth depends on what a later
    /// stage does, so the judgement belongs there, and the evidence has to reach it.
    struct VisibilityCut {
        let visible: [Suggestion]
        let hiddenRefutable: [Suggestion]
        /// Computed where the conformance index is already in hand, and carried out so the
        /// renderer can pair it with the suggestion count. See `CoverageHeadline`.
        let coverage: CoverageSummary
    }

    /// Bundle of resolved settings the discover pipeline pulls from
    /// `ConfigLoader` + `VocabularyLoader` + `effectiveTestDirectory`.
    /// V1.89 lint pass — carries the production-target `directory`
    /// too so `combineAndFilter` stays under the 5-param cap.
    struct PipelineSetup {
        let directory: URL
        let includePossible: Bool
        /// Effective docstring-advice setting; see `Config.docstringAdvice`.
        let docstringAdvice: Bool
        let vocabulary: Vocabulary
        let testDirectory: URL
        let packageRoot: URL?
        /// V1.32.C — Domain Template Packs (PRD §20.3). `nil` = no
        /// filter applied (all 10 templates run; current monolithic-
        /// registry behavior). Non-nil = post-discover filter to the
        /// supplied set of `templateName` values.
        let templateFilter: Set<String>?
        /// PROTOTYPE (2026-07-30) — `--require-corroboration`. When true, a suggestion whose
        /// score rests on a single positive signal loses its default visibility. Opt-in, and
        /// deliberately NOT a change to `Tier.init(forScore:)`. See `CorroborationRule` for
        /// the Q3 measurement that motivated it and the trade it makes.
        let requireCorroboration: Bool
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
    struct ExplicitOverrides {
        let vocabularyPath: URL?
        let configPath: URL?
        let testDirectory: URL?
        let packs: String?
    }
}
