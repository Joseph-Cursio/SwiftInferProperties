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

    // MARK: - TestLifter M5.4 — Codable round-trip fallback

    /// PRD §7.4 rung 5 — Codable round-trip fallback. Walks the
    /// post-strategist (M3) + post-mock (M4) suggestions and rebuilds
    /// any survivor whose `generator.source == .notYetComputed` AND
    /// whose generator-relevant type conforms to `Codable` (or both
    /// `Encodable` and `Decodable` separately) with a
    /// `.derivedCodableRoundTrip` source + `.medium` confidence.
    /// Strategist-derived (`.derivedMemberwise` / `.derivedCaseIterable`
    /// / `.derivedRawRepresentable` / `.registered`) and mock-inferred
    /// (`.inferredFromTests`) survivors are never overwritten — the
    /// `.notYetComputed` guard is the load-bearing precondition.
    ///
    /// Conformance lookup is textual + multi-decl-aware: each
    /// `TypeDecl.inheritedTypes` is a verbatim trimmed source name
    /// list (e.g. `["Codable"]`, `["Encodable", "Decodable"]`), and
    /// extensions emit their own `TypeDecl` per the M3 plan OD #2.
    /// `codableTypeNames(in:)` unions every `TypeDecl.name`'s
    /// inheritance lists across all matching primary + extension
    /// records, then matches `"Codable"` or `"Encodable" + "Decodable"`.
    ///
    /// Pure function over its inputs. The discover pipeline runs it as
    /// a third pass (after `apply(...)` + `applyMockInferredFallback(...)`).
    /// `liftedOrigin` and `mockGenerator` are preserved on rebuild so
    /// the lifted-pipeline accept-flow's provenance metadata stays
    /// intact through the Codable rebuild.
    public static func applyCodableRoundTripFallback(
        to suggestions: [Suggestion],
        generatorTypeByIdentity: [SuggestionIdentity: String],
        typeDecls: [TypeDecl]
    ) -> [Suggestion] {
        if generatorTypeByIdentity.isEmpty || typeDecls.isEmpty {
            return suggestions
        }
        let codableNames = codableTypeNames(in: typeDecls)
        if codableNames.isEmpty {
            return suggestions
        }
        return suggestions.map { suggestion in
            guard suggestion.generator.source == .notYetComputed,
                  let typeName = generatorTypeByIdentity[suggestion.identity],
                  codableNames.contains(typeName) else {
                return suggestion
            }
            return rebuildWithCodableRoundTrip(suggestion)
        }
    }

    /// Set of every type name in `typeDecls` whose unioned inheritance
    /// clauses (across primary decls + extensions) match `Codable` or
    /// `Encodable + Decodable`.
    static func codableTypeNames(in typeDecls: [TypeDecl]) -> Set<String> {
        var unionedConformances: [String: Set<String>] = [:]
        for decl in typeDecls {
            unionedConformances[decl.name, default: []].formUnion(decl.inheritedTypes)
        }
        var codableNames: Set<String> = []
        for (name, conformances) in unionedConformances where isCodable(conformances) {
            codableNames.insert(name)
        }
        return codableNames
    }

    private static func isCodable(_ conformances: Set<String>) -> Bool {
        if conformances.contains("Codable") {
            return true
        }
        return conformances.contains("Encodable") && conformances.contains("Decodable")
    }

    private static func rebuildWithCodableRoundTrip(_ suggestion: Suggestion) -> Suggestion {
        let metadata = GeneratorMetadata(
            source: .derivedCodableRoundTrip,
            confidence: .medium,
            sampling: suggestion.generator.sampling
        )
        return Suggestion(
            templateName: suggestion.templateName,
            evidence: suggestion.evidence,
            score: suggestion.score,
            generator: metadata,
            explainability: suggestion.explainability,
            identity: suggestion.identity,
            liftedOrigin: suggestion.liftedOrigin,
            mockGenerator: suggestion.mockGenerator
        )
    }
}
