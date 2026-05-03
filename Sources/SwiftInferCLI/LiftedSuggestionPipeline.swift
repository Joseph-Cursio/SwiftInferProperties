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
        constructionRecord: ConstructionRecord = ConstructionRecord(entries: [])
    ) -> [Suggestion] {
        guard !lifted.isEmpty else {
            return []
        }
        let suppressionKeys = Set(templateEngineSuggestions.map(\.crossValidationKey))
        let summariesByName = LiftedSuggestionRecovery.summariesByName(summaries)
        // Pair each lifted with its promoted Suggestion so we can build
        // the SuggestionIdentity → typeName index for GeneratorSelection
        // without parsing the synthetic evidence signature back out.
        let pairs = lifted.map { liftedItem -> (lifted: LiftedSuggestion, suggestion: Suggestion) in
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
        let surviving = pairs.filter { !suppressionKeys.contains($0.suggestion.crossValidationKey) }
        guard !surviving.isEmpty else {
            return []
        }
        let shapesByName = Dictionary(
            uniqueKeysWithValues: TypeShapeBuilder.shapes(from: typeDecls).map { ($0.name, $0) }
        )
        var generatorTypeByIdentity: [SuggestionIdentity: String] = [:]
        for pair in surviving {
            let annotations = pair.lifted.origin.flatMap { setupAnnotationsByOrigin[$0] } ?? [:]
            if let typeName = LiftedSuggestionRecovery.recoveredTypeName(
                for: pair.lifted,
                summariesByName: summariesByName,
                setupAnnotations: annotations
            ) {
                generatorTypeByIdentity[pair.suggestion.identity] = typeName
            }
        }
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
        // M5.4 — third pass. Walks survivors whose
        // `generator.source == .notYetComputed` (after the strategist
        // pass + the mock fallback pass have had their turns) and
        // rebuilds the ones whose generator-relevant type conforms to
        // Codable / Encodable+Decodable with .derivedCodableRoundTrip
        // + .medium. Strategist + mock survivors are preserved by the
        // .notYetComputed guard inside `applyCodableRoundTripFallback`.
        return GeneratorSelection.applyCodableRoundTripFallback(
            to: withMockFallback,
            generatorTypeByIdentity: generatorTypeByIdentity,
            typeDecls: typeDecls
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
