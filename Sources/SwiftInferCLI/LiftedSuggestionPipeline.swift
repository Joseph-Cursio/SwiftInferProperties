import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter

/// CLI-side integration of the TestLifter promotion + recovery +
/// generator inference + cross-validation suppression pipeline (M3.2).
///
/// Sits between `TemplateRegistry.discoverArtifacts` (which produces
/// the TemplateEngine-side `[Suggestion]`) and the tier filter in
/// `Discover+Pipeline.collectVisibleSuggestions`. Promotes each
/// `LiftedSuggestion` to a `Suggestion` via
/// `LiftedSuggestionRecovery`, runs the same `GeneratorSelection`
/// pass TemplateEngine uses for stdlib derivation, and drops any
/// promoted Suggestion whose `crossValidationKey` already matches a
/// TemplateEngine Suggestion (the +20 cross-validation signal already
/// communicates the corroboration; double-emitting would confuse the
/// `discover` reader and double-count in baseline / drift / decisions).
///
/// **The suppression invariant.** When `Sources/Foo/Codec.swift` has
/// `encode`/`decode` AND `Tests/FooTests/CodecTests.swift` has the
/// matching round-trip body, the visible stream contains exactly one
/// suggestion (the TemplateEngine `RoundTripTemplate` one with its
/// existing +20 cross-validation signal — already emitted by
/// `TemplateRegistry.applyCrossValidation` per the M1.5 wiring). The
/// promoted lifted Suggestion is suppressed. Verified by
/// `TestLifterCrossValidationTests` family + the new M3.4
/// `TestLifterSuppressionIntegrationTests`.
///
/// **The stream-entry payoff.** When the test body has a callee with
/// no matching production-side function (test-only helpers, or
/// scanner-skipped declarations), the promoted lifted Suggestion
/// survives suppression and enters the visible stream — exactly the
/// "TestLifter saw it but TemplateEngine missed it" case M3 was
/// designed to surface. With recovered types, the suggestion carries
/// the inferred generator; without them, `.todo` survives into the
/// accept-flow stub per PRD §16 #4.
public enum LiftedSuggestionPipeline {

    /// Tuple shape used by `promote(...)` to pair each input lifted record
    /// with its post-recovery `Suggestion`. Named so the `.map` closure
    /// stays under SwiftLint's 120-char line cap.
    fileprivate typealias LiftedPair = (lifted: LiftedSuggestion, suggestion: Suggestion)

    /// Promote each LiftedSuggestion, apply GeneratorSelection,
    /// suppress entries whose key matches a TemplateEngine suggestion,
    /// and return the survivors. The caller (`Discover+Pipeline`)
    /// unions the result with the TemplateEngine suggestions before
    /// the tier filter.
    ///
    /// **M4.2 — `setupAnnotationsByOrigin` second-tier recovery.** When
    /// non-empty, the per-`LiftedOrigin` annotation map (built by
    /// `TestLifter.discover` from `SetupRegionTypeAnnotationScanner`)
    /// is consulted by `LiftedSuggestionRecovery` when the
    /// FunctionSummary lookup misses. Pure additive — the parameter
    /// defaults to empty, so existing callers (unit tests, the M3.2
    /// integration paths) work unchanged.
    ///
    /// **M4.3 — `constructionRecord` mock-inferred fallback.** When
    /// non-empty, the corpus-wide construction record is queried by
    /// `MockGeneratorSynthesizer.synthesize(typeName:record:)` for
    /// every promoted Suggestion that exits `GeneratorSelection.apply`
    /// with `.notYetComputed` source. On a §13 ≥3-site dominant-shape
    /// hit, the Suggestion is rebuilt with `.inferredFromTests` source
    /// + `.low` confidence + the `mockGenerator` field populated.
    /// Strategist-derived generators are never overwritten — the
    /// fallback only fires on `.notYetComputed` survivors.
    ///
    /// **Plan deviation note.** The M4 plan (§ Sub-milestones, M4.3)
    /// called for the mock fallback to live as a `GeneratorSelection`
    /// extension. `GeneratorSelection` lives in `SwiftInferTemplates`
    /// which doesn't depend on `SwiftInferTestLifter` (where
    /// `ConstructionRecord` lives), so the extension placement would
    /// require a layering inversion. The mock fallback lives here in
    /// the CLI-side pipeline instead. OD #2 (a) "fire on both"
    /// (TemplateEngine + lifted) is *narrowed* to "lifted-only"
    /// in this commit to avoid the deeper Templates-layer refactor;
    /// the §13 numerical bar (≥50% of types with ≥3 same-shape
    /// construction sites get a Gen<T>) is addressed by the
    /// lifted-only path because lifted suggestions are the primary
    /// mock-synthesis target (test-only types whose generators come
    /// from observed test construction).
    public static func promote(
        lifted: [LiftedSuggestion],
        templateEngineSuggestions: [Suggestion],
        summaries: [FunctionSummary],
        typeDecls: [TypeDecl],
        setupAnnotationsByOrigin: [LiftedOrigin: [String: String]] = [:],
        constructionRecord: ConstructionRecord = ConstructionRecord(entries: []),
        domainCallSitesByConsumer: [String: [DomainCallSite]] = [:],
        equivalenceClassCandidates: [PartitionCandidate] = []
    ) -> [Suggestion] {
        let summariesByName = LiftedSuggestionRecovery.summariesByName(summaries)
        let liftedWithEquivalenceClasses = unionLiftedWithEquivalenceClasses(
            lifted: lifted,
            candidates: equivalenceClassCandidates,
            summariesByName: summariesByName,
            typeDecls: typeDecls
        )
        guard !liftedWithEquivalenceClasses.isEmpty else {
            return []
        }
        let suppressionKeys = Set(templateEngineSuggestions.map(\.crossValidationKey))
        let pairs = pairLiftedWithRecoveredSuggestions(
            liftedWithEquivalenceClasses,
            summariesByName: summariesByName,
            setupAnnotationsByOrigin: setupAnnotationsByOrigin
        )
        let surviving = pairs.filter { !suppressionKeys.contains($0.suggestion.crossValidationKey) }
        guard !surviving.isEmpty else {
            return []
        }
        let shapesByName = Dictionary(
            uniqueKeysWithValues: TypeShapeBuilder.shapes(from: typeDecls).map { ($0.name, $0) }
        )
        let generatorTypeByIdentity = buildGeneratorTypeIndex(
            from: surviving,
            summariesByName: summariesByName,
            setupAnnotationsByOrigin: setupAnnotationsByOrigin
        )
        let withStrategistGenerators = GeneratorSelection.apply(
            to: surviving.map(\.suggestion),
            generatorTypeByIdentity: generatorTypeByIdentity,
            shapesByName: shapesByName
        )
        let withMockFallback = applyMockInferredFallback(
            to: withStrategistGenerators,
            generatorTypeByIdentity: generatorTypeByIdentity,
            record: constructionRecord
        )
        // M10.3 — domain inference pass. Walks each round-trip
        // suggestion that exited the mock-fallback pass with a populated
        // `mockGenerator`, queries `domainCallSitesByConsumer` for the
        // reverse function's call sites, and (when homogeneity holds)
        // attaches a `DomainHint` to `MockGenerator.domainHint`. No-op
        // when the map is empty (default-empty parameter; existing
        // callers pre-M10.3 are unchanged).
        let withDomainHints = applyDomainInference(
            to: withMockFallback,
            summariesByName: summariesByName,
            domainCallSitesByConsumer: domainCallSitesByConsumer
        )
        // M5.4 — third pass. Walks survivors whose
        // `generator.source == .notYetComputed` (after the strategist
        // pass + the mock fallback pass have had their turns) and
        // rebuilds the ones whose generator-relevant type conforms to
        // Codable / Encodable+Decodable with .derivedCodableRoundTrip
        // + .medium. Strategist + mock survivors are preserved by the
        // .notYetComputed guard inside `applyCodableRoundTripFallback`.
        return GeneratorSelection.applyCodableRoundTripFallback(
            to: withDomainHints,
            generatorTypeByIdentity: generatorTypeByIdentity,
            typeDecls: typeDecls
        )
    }

    /// M11.2 — fold equivalence-class lifted suggestions into the
    /// promotion stream BEFORE the empty-input early return. Their
    /// synthetic crossValidationKey (`templateName: "equivalence-class"`)
    /// never matches any TemplateEngine template, so the suppression
    /// filter naturally lets them through.
    private static func unionLiftedWithEquivalenceClasses(
        lifted: [LiftedSuggestion],
        candidates: [PartitionCandidate],
        summariesByName: [String: FunctionSummary],
        typeDecls: [TypeDecl]
    ) -> [LiftedSuggestion] {
        lifted + equivalenceClassLifted(
            from: candidates,
            summariesByName: summariesByName,
            typeDecls: typeDecls
        )
    }

    /// Pair each lifted with its promoted Suggestion so we can build
    /// the `SuggestionIdentity → typeName` index for GeneratorSelection
    /// without parsing the synthetic evidence signature back out.
    private static func pairLiftedWithRecoveredSuggestions(
        _ lifted: [LiftedSuggestion],
        summariesByName: [String: FunctionSummary],
        setupAnnotationsByOrigin: [LiftedOrigin: [String: String]]
    ) -> [LiftedPair] {
        lifted.map { liftedItem in
            let annotations = liftedItem.origin.flatMap { setupAnnotationsByOrigin[$0] } ?? [:]
            return (
                liftedItem,
                LiftedSuggestionRecovery.recover(
                    liftedItem,
                    summariesByName: summariesByName,
                    setupAnnotations: annotations
                )
            )
        }
    }

    private static func buildGeneratorTypeIndex(
        from pairs: [(lifted: LiftedSuggestion, suggestion: Suggestion)],
        summariesByName: [String: FunctionSummary],
        setupAnnotationsByOrigin: [LiftedOrigin: [String: String]]
    ) -> [SuggestionIdentity: String] {
        var index: [SuggestionIdentity: String] = [:]
        for pair in pairs {
            let annotations = pair.lifted.origin.flatMap { setupAnnotationsByOrigin[$0] } ?? [:]
            if let typeName = LiftedSuggestionRecovery.recoveredTypeName(
                for: pair.lifted,
                summariesByName: summariesByName,
                setupAnnotations: annotations
            ) {
                index[pair.suggestion.identity] = typeName
            }
        }
        return index
    }

    /// M10.3 — for each round-trip suggestion (`templateName == "round-trip"`)
    /// whose `mockGenerator` was populated by the M4.3 fallback,
    /// derives the `(forward, reverse)` pair from the suggestion's
    /// `evidence` (`evidence[0]` is forward, `evidence[1]` is reverse),
    /// looks up the reverse function's call sites in
    /// `domainCallSitesByConsumer`, runs the inferrer with the forward
    /// function's `FunctionSummary`, and rebuilds the suggestion with
    /// `MockGenerator.domainHint` populated. Suggestions without a
    /// mock generator, non-round-trip suggestions, missing pair info,
    /// and inferrer-rejected cases pass through unchanged.
    ///
    /// **Limitation (deferred):** the producer-arg-generatable veto
    /// (M10 plan OD #4) is not currently computed — the pass passes
    /// `producerArgGeneratable: true` unconditionally. The other three
    /// vetoes (throws / async / multi-arg) ARE checked. A `.todo` type
    /// override falls back to the existing `\(typeName).gen()`
    /// surface, matching the M3+ `.todo` posture.
    ///
    /// Exposed for testing via the `applyDomainInferenceForTesting(...)`
    /// `internal` wrapper below; production callers reach this path
    /// through `promote(...)`'s pipeline composition.
    private static func applyDomainInference(
        to suggestions: [Suggestion],
        summariesByName: [String: FunctionSummary],
        domainCallSitesByConsumer: [String: [DomainCallSite]]
    ) -> [Suggestion] {
        guard !domainCallSitesByConsumer.isEmpty else {
            return suggestions
        }
        return suggestions.map { suggestion in
            guard suggestion.templateName == "round-trip",
                  let mockGenerator = suggestion.mockGenerator,
                  suggestion.evidence.count == 2 else {
                return suggestion
            }
            let forwardName = bareFunctionName(suggestion.evidence[0].displayName)
            let reverseName = bareFunctionName(suggestion.evidence[1].displayName)
            guard let forwardSummary = summariesByName[forwardName] else {
                return suggestion
            }
            let sites = domainCallSitesByConsumer[reverseName] ?? []
            let pair = RoundTripPair(
                forwardName: forwardName,
                reverseName: reverseName,
                domainTypeName: mockGenerator.typeName
            )
            guard let hint = DomainInferrer.infer(
                pair: pair,
                forwardSummary: forwardSummary,
                sites: sites,
                setupBindings: [:],
                producerArgGeneratable: true
            ) else {
                return suggestion
            }
            let updated = MockGenerator(
                typeName: mockGenerator.typeName,
                argumentSpec: mockGenerator.argumentSpec,
                siteCount: mockGenerator.siteCount,
                preconditionHints: mockGenerator.preconditionHints,
                domainHint: hint
            )
            return Suggestion(
                templateName: suggestion.templateName,
                evidence: suggestion.evidence,
                score: suggestion.score,
                generator: suggestion.generator,
                explainability: suggestion.explainability,
                identity: suggestion.identity,
                liftedOrigin: suggestion.liftedOrigin,
                mockGenerator: updated
            )
        }
    }

    /// Strip parameter labels from an `Evidence.displayName` like
    /// `"encode(_:)"` to recover the bare function name `"encode"` for
    /// `summariesByName` lookup + matching against the M10.3 corpus
    /// call-site map's trailing-identifier keys.
    private static func bareFunctionName(_ displayName: String) -> String {
        if let openParen = displayName.firstIndex(of: "(") {
            return String(displayName[..<openParen])
        }
        return displayName
    }

    /// Internal surface for `DomainInferencePipelineTests`. Forwards
    /// to the private `applyDomainInference(...)` so the test target
    /// can exercise the M10.3 pass with synthetic inputs without
    /// staging the full M4.3 mock-fallback prerequisite path.
    internal static func applyDomainInferenceForTesting(
        to suggestions: [Suggestion],
        summariesByName: [String: FunctionSummary],
        domainCallSitesByConsumer: [String: [DomainCallSite]]
    ) -> [Suggestion] {
        applyDomainInference(
            to: suggestions,
            summariesByName: summariesByName,
            domainCallSitesByConsumer: domainCallSitesByConsumer
        )
    }

    /// Second-pass mock-inferred fallback (M4.3). Walks suggestions
    /// whose `generator.source == .notYetComputed` after the M3
    /// strategist pass and queries `MockGeneratorSynthesizer.synthesize(
    /// typeName:record:)` for each. On a hit, the Suggestion is
    /// rebuilt with `.inferredFromTests` source + `.low` confidence +
    /// the `mockGenerator` field populated. Empty-record short-circuits
    /// (no synthesis possible, return inputs unchanged).
    private static func applyMockInferredFallback(
        to suggestions: [Suggestion],
        generatorTypeByIdentity: [SuggestionIdentity: String],
        record: ConstructionRecord
    ) -> [Suggestion] {
        if record.entries.isEmpty {
            return suggestions
        }
        return suggestions.map { suggestion in
            guard suggestion.generator.source == .notYetComputed,
                  let typeName = generatorTypeByIdentity[suggestion.identity],
                  let mockGenerator = MockGeneratorSynthesizer.synthesize(
                      typeName: typeName,
                      record: record
                  ) else {
                return suggestion
            }
            return rebuild(suggestion, withMockGenerator: mockGenerator)
        }
    }

    private static func rebuild(
        _ suggestion: Suggestion,
        withMockGenerator mockGenerator: MockGenerator
    ) -> Suggestion {
        let mockMetadata = GeneratorMetadata(
            source: .inferredFromTests,
            confidence: .low,
            sampling: suggestion.generator.sampling
        )
        return Suggestion(
            templateName: suggestion.templateName,
            evidence: suggestion.evidence,
            score: suggestion.score,
            generator: mockMetadata,
            explainability: suggestion.explainability,
            identity: suggestion.identity,
            liftedOrigin: suggestion.liftedOrigin,
            mockGenerator: mockGenerator
        )
    }

}
