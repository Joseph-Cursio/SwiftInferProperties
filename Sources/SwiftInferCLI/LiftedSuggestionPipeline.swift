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
    public static func promote(
        lifted: [LiftedSuggestion],
        templateEngineSuggestions: [Suggestion],
        summaries: [FunctionSummary],
        typeDecls: [TypeDecl],
        setupAnnotationsByOrigin: [LiftedOrigin: [String: String]] = [:]
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
        return GeneratorSelection.apply(
            to: surviving.map(\.suggestion),
            generatorTypeByIdentity: generatorTypeByIdentity,
            shapesByName: shapesByName
        )
    }
}
