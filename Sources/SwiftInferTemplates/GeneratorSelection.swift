import ProtoLawCore
import SwiftInferCore

/// Generator-selection layer per the M4 plan §M4.2. Walks
/// post-contradiction-filter `[Suggestion]` records and, for each
/// suggestion whose generator-relevant type appears in the corpus's
/// `TypeShape` index (M4.1), calls
/// `ProtoLawCore.DerivationStrategist.strategy(for:)` and rebuilds the
/// suggestion with a populated `GeneratorMetadata.source` +
/// `confidence`. Suggestions whose type isn't in the index pass
/// through with their existing `m1Placeholder` metadata — per the M4
/// plan's open decision #2 default ("(a) Skip selection for non-corpus
/// types"), stdlib-only properties stay `.notYetComputed` until M5's
/// annotation API gives users a way to opt them into a generator.
///
/// Pure function over its inputs. The discover pipeline runs it
/// after the contradiction filter (so dropped suggestions aren't
/// rebuilt) and before cross-validation (so cross-validated
/// suggestions show their generator info too).
public enum GeneratorSelection {

    /// Apply generator selection. `generatorTypeByIdentity` maps each
    /// suggestion's `identity` to the source-text spelling of its
    /// generator-relevant type — for the M2 templates that's `T`
    /// (idempotence's `T -> T`, round-trip's forward `T -> U`,
    /// commutativity / associativity / identity-element's `(T, T) -> T`).
    /// `shapesByName` is the result of folding `corpus.typeDecls` via
    /// `TypeShapeBuilder.shapes(from:)`, keyed by `TypeShape.name`.
    public static func apply(
        to suggestions: [Suggestion],
        generatorTypeByIdentity: [SuggestionIdentity: String],
        shapesByName: [String: TypeShape]
    ) -> [Suggestion] {
        if shapesByName.isEmpty || generatorTypeByIdentity.isEmpty {
            return suggestions
        }
        return suggestions.map { suggestion in
            guard let typeName = generatorTypeByIdentity[suggestion.identity],
                  let shape = shapesByName[typeName] else {
                return suggestion
            }
            let strategy = DerivationStrategist.strategy(for: shape)
            let metadata = makeMetadata(
                strategy: strategy,
                sampling: suggestion.generator.sampling
            )
            return rebuild(suggestion, withGenerator: metadata)
        }
    }

    /// Per the M4 plan's open decision #5 confidence calibration table.
    /// The mapping from `DerivationStrategy` to
    /// `GeneratorMetadata.Source` + `Confidence`:
    ///
    /// | DerivationStrategy        | Source                    | Confidence |
    /// | ------------------------- | ------------------------- | ---------- |
    /// | `.userGen`                | `.registered`             | `.high`    |
    /// | `.caseIterable`           | `.derivedCaseIterable`    | `.high`    |
    /// | `.rawRepresentable(_)`    | `.derivedRawRepresentable`| `.high`    |
    /// | `.memberwiseArbitrary(_)` | `.derivedMemberwise`      | `.medium`  |
    /// | `.todo(reason:)`          | `.todo`                   | `nil`      |
    static func sourceAndConfidence(
        for strategy: DerivationStrategy
    ) -> (GeneratorMetadata.Source, GeneratorMetadata.Confidence?) {
        switch strategy {
        case .userGen:
            return (.registered, .high)
        case .caseIterable:
            return (.derivedCaseIterable, .high)
        case .rawRepresentable:
            return (.derivedRawRepresentable, .high)
        case .memberwiseArbitrary:
            return (.derivedMemberwise, .medium)
        case .todo:
            return (.todo, nil)
        }
    }

    private static func makeMetadata(
        strategy: DerivationStrategy,
        sampling: GeneratorMetadata.SamplingResult
    ) -> GeneratorMetadata {
        let (source, confidence) = sourceAndConfidence(for: strategy)
        return GeneratorMetadata(
            source: source,
            confidence: confidence,
            sampling: sampling
        )
    }

    private static func rebuild(
        _ suggestion: Suggestion,
        withGenerator metadata: GeneratorMetadata
    ) -> Suggestion {
        Suggestion(
            templateName: suggestion.templateName,
            evidence: suggestion.evidence,
            score: suggestion.score,
            generator: metadata,
            explainability: suggestion.explainability,
            identity: suggestion.identity
        )
    }
}
