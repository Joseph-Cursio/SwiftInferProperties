import Foundation
import SwiftInferCore

/// V1.18.A — read-only resolver context threaded into per-summary and
/// per-pair collection helpers. Bundled to keep helper signatures under
/// SwiftLint's parameter-count ceiling as more resolvers are added (the
/// v1.18 plan adds `carrierKindResolver`; v1.19 adds `liftedTransformations`).
/// Mirrors `EquatableResolver` + `inheritedTypesByName` being built once
/// per `discover` call and reused across every per-template `suggest`
/// invocation.
struct CollectionResolverContext {
    let vocabulary: Vocabulary
    let inheritedTypesByName: [String: Set<String>]
    let carrierKindResolver: CarrierKindResolver?
    /// V1.19.A — corpus-wide lifted-transformation set, available to the
    /// V1.19.B-D template fan-out sites (Idempotence, IdentityElement,
    /// Composition, InversePair). Empty when no mutating-func summaries
    /// pass the strict value-semantic carrier gate.
    let liftedTransformations: [LiftedTransformation]
}

/// Mutable accumulator used inside `collectSuggestions`. Keeps the
/// three parallel collections in one place so the per-summary /
/// per-pair helpers don't have to thread three `inout` parameters
/// each. `contradictionTypes` feeds the M3.4 detector;
/// `generatorTypes` feeds the M4.2 selector. Both are sparse — only
/// suggestions that need per-suggestion type context are recorded.
struct SuggestionCollector {
    var suggestions: [Suggestion] = []
    var contradictionTypes: [SuggestionIdentity: [String]] = [:]
    var generatorTypes: [SuggestionIdentity: String] = [:]

    mutating func record(
        _ suggestion: Suggestion,
        contradictionTypes contradictionTypeValues: [String]? = nil,
        generatorType: String? = nil
    ) {
        suggestions.append(suggestion)
        if let contradictionTypeValues {
            contradictionTypes[suggestion.identity] = contradictionTypeValues
        }
        if let generatorType {
            generatorTypes[suggestion.identity] = generatorType
        }
    }
}

extension TemplateRegistry {

    /// Run every shipped template against `summaries` + `identities`
    /// and bundle the resulting suggestions with their per-identity
    /// type context. Pulled out of `discover` so the orchestration
    /// function stays readable as a five-step pipeline (collect →
    /// drop → select generator → cross-validate → sort).
    ///
    /// V1.5.2 — `inheritedTypesByName` is the corpus-wide name →
    /// inheritance-clause-union index built by
    /// `ProtocolCoverageMap.inheritedTypesIndex(from:)`; threaded into
    /// the six algebraic templates whose `protocolCoverageVeto(...)`
    /// helpers suppress suggestions whose property is already covered
    /// by the candidate type's existing conformance.
    static func collectSuggestions(
        summaries: [FunctionSummary],
        identities: [IdentityCandidate],
        vocabulary: Vocabulary,
        equatableResolver: EquatableResolver,
        inheritedTypesByName: [String: Set<String>] = [:],
        carrierKindResolver: CarrierKindResolver? = nil,
        liftedTransformations: [LiftedTransformation] = []
    ) -> SuggestionCollector {
        // Corpus-wide union of names referenced as the closure-position
        // argument of any `.reduce(_, X)` call — feeds the associativity
        // reducer/builder-usage signal (PRD §5.3, +20). Computed once per
        // discover so per-summary template calls are O(1) lookups.
        let reducerOps: Set<String> = Set(summaries.flatMap(\.bodySignals.reducerOpsReferenced))
        // Subset whose `.reduce(seed, op)` seed was identity-shaped — feeds
        // identity-element's accumulator-with-empty-seed signal (+20).
        let opsWithIdentitySeed: Set<String> = Set(
            summaries.flatMap(\.bodySignals.reducerOpsWithIdentitySeed)
        )
        let context = CollectionResolverContext(
            vocabulary: vocabulary,
            inheritedTypesByName: inheritedTypesByName,
            carrierKindResolver: carrierKindResolver,
            liftedTransformations: liftedTransformations
        )
        var collector = SuggestionCollector()
        for summary in summaries {
            collectPerSummarySuggestions(
                summary: summary,
                reducerOps: reducerOps,
                context: context,
                into: &collector
            )
        }
        for pair in FunctionPairing.candidates(in: summaries) {
            collectPerPairSuggestions(
                pair: pair,
                equatableResolver: equatableResolver,
                context: context,
                into: &collector
            )
        }
        collectIdentityElementSuggestions(
            summaries: summaries,
            identities: identities,
            opsWithIdentitySeed: opsWithIdentitySeed,
            context: context,
            into: &collector
        )
        collectDualStyleSuggestions(
            summaries: summaries,
            context: context,
            into: &collector
        )
        collectPartitionSuggestions(
            summaries: summaries,
            into: &collector
        )
        collectLiftedSuggestions(
            lifted: liftedTransformations,
            identities: identities,
            context: context,
            into: &collector
        )
        return collector
    }

    /// IdentityElement template fan-out — kept as a helper so
    /// `collectSuggestions` stays under the SwiftLint function-body
    /// budget as new template fan-outs accumulate (V1.18.C dual-style,
    /// V1.19.B lift admission).
    private static func collectIdentityElementSuggestions(
        summaries: [FunctionSummary],
        identities: [IdentityCandidate],
        opsWithIdentitySeed: Set<String>,
        context: CollectionResolverContext,
        into collector: inout SuggestionCollector
    ) {
        for pair in IdentityElementPairing.candidates(in: summaries, identities: identities) {
            if let suggestion = IdentityElementTemplate.suggest(
                for: pair,
                opsWithIdentitySeed: opsWithIdentitySeed,
                inheritedTypesByName: context.inheritedTypesByName,
                carrierKindResolver: context.carrierKindResolver
            ) {
                collector.record(suggestion, generatorType: generatorType(for: pair.operation))
            }
        }
    }

    /// B3 — the partition / tiling law: the parts must reconstitute the whole.
    ///
    /// The catalogue was algebraic and calibrated on libraries. Application code is not shaped like
    /// an algebra: the most valuable property in a file-sync client is not a semigroup, it is *the
    /// chunks tile the payload exactly* — and no template in the set could say it. That gap is why a
    /// real app produced six suggestions and **zero refutable claims**.
    private static func collectPartitionSuggestions(
        summaries: [FunctionSummary],
        into collector: inout SuggestionCollector
    ) {
        for shape in PartitionPairing.candidates(in: summaries) {
            if let suggestion = PartitionTemplate.suggest(for: shape) {
                collector.record(suggestion, generatorType: shape.typeName)
            }
        }
    }

    private static func collectDualStyleSuggestions(
        summaries: [FunctionSummary],
        context: CollectionResolverContext,
        into collector: inout SuggestionCollector
    ) {
        for pair in DualStylePairing.candidates(in: summaries, vocabulary: context.vocabulary) {
            if let suggestion = DualStyleConsistencyTemplate.suggest(
                for: pair,
                carrierKindResolver: context.carrierKindResolver
            ) {
                collector.record(
                    suggestion,
                    generatorType: pair.mutatingMember.containingTypeName
                )
            }
        }
    }

    /// V1.19.B-D — emit lifted-mutation suggestions for each admissible
    /// `LiftedTransformation`. v1.19 fans out across IdempotenceTemplate
    /// (V1.19.B), CompositionTemplate (V1.19.C), LiftedIdentityElementPairing +
    /// IdentityElementTemplate (V1.19.C). InversePairTemplate lift admission
    /// (V1.19.D) hooks in here next. No-op when no carrier-kind resolver is
    /// supplied (the lifted-suggest path always emits the carrier signal so
    /// the resolver is load-bearing).
    private static func collectLiftedSuggestions(
        lifted: [LiftedTransformation],
        identities: [IdentityCandidate],
        context: CollectionResolverContext,
        into collector: inout SuggestionCollector
    ) {
        guard let resolver = context.carrierKindResolver else { return }
        for transformation in lifted {
            collectLiftedTemplatesForOne(
                transformation: transformation,
                context: context,
                resolver: resolver,
                into: &collector
            )
        }
        for pair in LiftedIdentityElementPairing.candidates(
            in: lifted,
            identities: identities
        ) {
            if let suggestion = IdentityElementTemplate.suggest(
                forLifted: pair,
                carrierKindResolver: resolver
            ) {
                collector.record(suggestion, generatorType: pair.operation.carrier)
            }
        }
        for pair in InverseLiftedPairing.candidates(
            in: lifted,
            vocabulary: context.vocabulary
        ) {
            if let suggestion = InversePairTemplate.suggest(
                forLifted: pair,
                carrierKindResolver: resolver
            ) {
                collector.record(suggestion, generatorType: pair.forward.carrier)
            }
        }
    }

    /// Per-`LiftedTransformation` template fan-out. Idempotence (V1.19.B)
    /// and Composition (V1.19.C) both score against a single transformation;
    /// pair-based templates (LiftedIdentityElementPairing, V1.19.D's
    /// InverseLiftedPairing) iterate at the call site.
    private static func collectLiftedTemplatesForOne(
        transformation: LiftedTransformation,
        context: CollectionResolverContext,
        resolver: CarrierKindResolver,
        into collector: inout SuggestionCollector
    ) {
        if let suggestion = IdempotenceTemplate.suggest(
            forLifted: transformation,
            vocabulary: context.vocabulary,
            inheritedTypesByName: context.inheritedTypesByName,
            carrierKindResolver: resolver
        ) {
            collector.record(suggestion, generatorType: transformation.carrier)
        }
        if let suggestion = CompositionTemplate.suggest(
            forLifted: transformation,
            vocabulary: context.vocabulary,
            carrierKindResolver: resolver
        ) {
            collector.record(suggestion, generatorType: transformation.carrier)
        }
    }

    /// Idempotence + commutativity + associativity all fire per
    /// summary; this helper keeps the per-summary loop body readable
    /// by encapsulating the constructions in one place.
    private static func collectPerSummarySuggestions(
        summary: FunctionSummary,
        reducerOps: Set<String>,
        context: CollectionResolverContext,
        into collector: inout SuggestionCollector
    ) {
        let summaryGenType = generatorType(for: summary)
        if let suggestion = IdempotenceTemplate.suggest(
            for: summary,
            vocabulary: context.vocabulary,
            inheritedTypesByName: context.inheritedTypesByName,
            carrierKindResolver: context.carrierKindResolver
        ) {
            collector.record(suggestion, generatorType: summaryGenType)
        }
        if let suggestion = CommutativityTemplate.suggest(
            for: summary,
            vocabulary: context.vocabulary,
            inheritedTypesByName: context.inheritedTypesByName
        ) {
            collector.record(
                suggestion,
                contradictionTypes: commutativityTypes(for: summary),
                generatorType: summaryGenType
            )
        }
        if let suggestion = AssociativityTemplate.suggest(
            for: summary,
            vocabulary: context.vocabulary,
            reducerOps: reducerOps,
            inheritedTypesByName: context.inheritedTypesByName
        ) {
            collector.record(suggestion, generatorType: summaryGenType)
        }
        if let suggestion = MonotonicityTemplate.suggest(for: summary, vocabulary: context.vocabulary) {
            collector.record(suggestion, generatorType: summaryGenType)
        }
        if let suggestion = InvariantPreservationTemplate.suggest(for: summary) {
            collector.record(suggestion, generatorType: summaryGenType)
        }
    }

    /// Round-trip + inverse-pair both fire per pair. `InversePairTemplate`
    /// gates internally on `EquatableResolver` so Equatable T defers to
    /// RoundTrip and only `.notEquatable` / `.unknown` fire here. No
    /// `contradictionTypes` plumbed for InversePair — ContradictionDetector
    /// would otherwise drop the very suggestions this template is
    /// designed to surface.
    private static func collectPerPairSuggestions(
        pair: FunctionPair,
        equatableResolver: EquatableResolver,
        context: CollectionResolverContext,
        into collector: inout SuggestionCollector
    ) {
        if let suggestion = RoundTripTemplate.suggest(
            for: pair,
            vocabulary: context.vocabulary,
            inheritedTypesByName: context.inheritedTypesByName,
            carrierKindResolver: context.carrierKindResolver
        ) {
            collector.record(
                suggestion,
                contradictionTypes: roundTripTypes(for: pair),
                generatorType: generatorType(for: pair)
            )
        }
        if let suggestion = InversePairTemplate.suggest(
            for: pair,
            vocabulary: context.vocabulary,
            equatableResolver: equatableResolver,
            inheritedTypesByName: context.inheritedTypesByName,
            carrierKindResolver: context.carrierKindResolver
        ) {
            collector.record(suggestion, generatorType: generatorType(for: pair))
        }
    }

    /// PRD §5.6 #2 — every type that has to classify Equatable for the
    /// commutativity suggestion to be testable. The type pattern guard
    /// in `CommutativityTemplate` enforces param[0] == param[1] ==
    /// return, but the detector is robust to template-side changes by
    /// listing all three.
    static func commutativityTypes(for summary: FunctionSummary) -> [String] {
        var types = summary.parameters.map(\.typeText)
        if let returnType = summary.returnTypeText {
            types.append(returnType)
        }
        return types
    }

    /// Generator-relevant `T` for a single-summary template
    /// (idempotence's `T -> T`, commutativity / associativity /
    /// identity-element's `(T, T) -> T`).
    static func generatorType(for summary: FunctionSummary) -> String? {
        summary.parameters.first?.typeText
    }

    /// Generator-relevant `T` for the round-trip template. Picks the
    /// forward half's parameter type — the test sampled from `T` then
    /// asserts `g(f(t)) == t`.
    static func generatorType(for pair: FunctionPair) -> String? {
        pair.forward.parameters.first?.typeText
    }

    /// PRD §5.6 #3 — domain and codomain on both halves of the
    /// round-trip pair.
    static func roundTripTypes(for pair: FunctionPair) -> [String] {
        var types: [String] = []
        types.append(contentsOf: pair.forward.parameters.map(\.typeText))
        if let returnType = pair.forward.returnTypeText {
            types.append(returnType)
        }
        types.append(contentsOf: pair.reverse.parameters.map(\.typeText))
        if let returnType = pair.reverse.returnTypeText {
            types.append(returnType)
        }
        return types
    }
}
