import PropertyLawCore
import SwiftInferCore

/// Generator-selection layer per the M4 plan §M4.2. Walks
/// post-contradiction-filter `[Suggestion]` records and, for each
/// suggestion whose generator-relevant type appears in the corpus's
/// `TypeShape` index (M4.1), calls
/// `PropertyLawCore.DerivationStrategist.strategy(for:)` and rebuilds the
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
        shapesByName: [String: TypeShape],
        registeredGenerators: [String: RegisteredGenerator] = [:]
    ) -> [Suggestion] {
        if shapesByName.isEmpty || generatorTypeByIdentity.isEmpty {
            return suggestions
        }
        // WS-6 Slice 1 — recursive nested-type resolution at discover time. Build a
        // `GeneratorResolver` over the whole corpus once, then pass its
        // `customTypeGenerator` as the `resolve` closure so a carrier that is a
        // struct/enum with nested custom-type members or init-params *derives*
        // (the resolver inlines each nested type's generator or references
        // `Type.gen()`) instead of dead-ending at `.todo`. Nested types external to
        // the corpus still resolve to nil → `.todo`, unchanged. This affects only
        // the `discover` command's generated output — verify re-derives from the
        // persisted shape (WS-6 Slice 2 threads the resolver there separately).
        let resolver = GeneratorResolver(types: Array(shapesByName.values))
        // Road-test #10 — a project-registered generator for an external type the
        // resolver can't reach (Yams `Node`) is consulted *before* the corpus
        // resolver, so a carrier gated at `.todo` solely by that member composes
        // the rest of itself instead. Wrapping the resolve closure honours the
        // user's verbatim expression + imports without a kit change (the corpus
        // resolver only ever returns `Type.gen()` for its own `hasUserGen` shapes).
        let resolve = registeredResolve(base: resolver.customTypeGenerator, registeredGenerators)
        return suggestions.map { suggestion in
            guard let typeName = generatorTypeByIdentity[suggestion.identity] else {
                return suggestion
            }
            if let shape = shapesByName[typeName] {
                let strategy = DerivationStrategist.strategy(
                    for: shape,
                    resolve: resolve
                )
                return rebuild(
                    suggestion,
                    withGenerator: makeMetadata(strategy: strategy, sampling: suggestion.generator.sampling)
                )
            }
            // Fix 1 (road-test): the carrier isn't a corpus struct/enum — it's a
            // stdlib / collection / composite type (`String`, `[String]`,
            // `[String: Int]`, a composite of resolvable leaves). The M4 default
            // skipped these to `.notYetComputed`, but app kernels are overwhelmingly
            // stdlib/collection-typed, and `CompositeMemberParser` already derives
            // them (it is what the accept path uses). Only fall through to
            // `.notYetComputed` when even it can't — an external / unrecognized type.
            if DerivationStrategist.composedGenerator(
                forTypeName: typeName,
                resolve: resolve
            ) != nil {
                let metadata = GeneratorMetadata(
                    source: .derivedComposite,
                    confidence: .high,
                    sampling: suggestion.generator.sampling
                )
                return rebuild(suggestion, withGenerator: metadata)
            }
            return suggestion
        }
    }

    /// Wrap the corpus resolver so a project-registered generator
    /// (`Vocabulary.registeredGenerators`) is consulted first, falling back to
    /// the corpus resolver for everything else. Returns `base` unchanged when
    /// no generators are registered (the common case — zero overhead).
    private static func registeredResolve(
        base: @escaping DerivationStrategist.CustomTypeResolver,
        _ registeredGenerators: [String: RegisteredGenerator]
    ) -> DerivationStrategist.CustomTypeResolver {
        if registeredGenerators.isEmpty {
            return base
        }
        return { name in
            if let registered = registeredGenerators[name] {
                return DerivationStrategist.ComposedGenerator(
                    expression: registered.expression,
                    requiredImports: Set(registered.imports)
                )
            }
            return base(name)
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

        case .initializerBased:
            return (.derivedInitializer, .medium)

        case .enumCases:
            return (.derivedEnumCases, .medium)

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

    /// **Mutate a copy. Never rebuild field-by-field.**
    ///
    /// This used to reconstruct `Suggestion` argument-by-argument, and the comment it carried told
    /// the story: *"the generator-carrier must survive the generator-metadata rebuild; omitting it
    /// silently reset it to nil … this dropped monotonicity's param-domain carrier set in V1.151."*
    ///
    /// The lesson was written down and the trap was left armed, because the omitted argument has a
    /// default and the compiler says nothing. It caught the very next field: `generatorRecipes` — the
    /// half of a law that decides whether it can fail — vanished here, and the partition law reached
    /// the reader with no generator at all.
    private static func rebuild(
        _ suggestion: Suggestion,
        withGenerator metadata: GeneratorMetadata
    ) -> Suggestion {
        suggestion.withGenerator(metadata)
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
        return suggestion.withGenerator(metadata)
    }
}
