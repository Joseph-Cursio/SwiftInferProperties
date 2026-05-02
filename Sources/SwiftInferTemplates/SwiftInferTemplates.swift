import Foundation
import SwiftInferCore

// swiftlint:disable file_length type_body_length
// M8.4.a added DiscoverArtifacts + discoverArtifacts(in:) on top of the
// existing TemplateRegistry surface, pushing both file_length (>400)
// and the TemplateRegistry enum's type_body_length (>250) past their
// caps. Splitting would scatter the orchestration entry points across
// multiple files for no reader benefit — every entry point shares the
// SuggestionCollector / per-summary helpers / cross-validation seam.

/// SwiftInferTemplates — TemplateEngine template registry.
///
/// PRD v0.3 §5.2 specifies eight shipped templates: round-trip, idempotence,
/// commutativity, associativity, monotonicity, identity-element,
/// invariant-preservation, inverse-pair. M1.3 shipped **idempotence**; M1.4
/// adds **round-trip** + cross-function pairing; M2.3 adds **commutativity**;
/// M2.4 adds **associativity** with reducer/builder usage as a new
/// type-flow signal; M2.5 adds **identity-element** with op + identity
/// constant cross-pairing and an accumulator-with-empty-seed type-flow
/// signal; subsequent milestones add the remaining three.
public enum SwiftInferTemplates {}

/// Static registry that orchestrates every M1 template against a corpus of
/// `FunctionSummary` records. Kept in `SwiftInferTemplates` (rather than the
/// CLI) so the discovery pipeline is reachable from tests without going
/// through ArgumentParser, and so v1.1's constraint-engine upgrade has a
/// single seam to slot into.
public enum TemplateRegistry {

    /// Run every M1 template against `summaries`. Output is sorted by
    /// (file path, line) of the first evidence row so the byte-identical-
    /// reproducibility guarantee (PRD §16 #6) holds across runs.
    ///
    /// `vocabulary` is the project-extensible naming layer per PRD §4.5;
    /// templates consult it alongside their curated lists. Defaults to
    /// `.empty` so M1 call sites that haven't been updated for the M2
    /// vocabulary plumbing keep compiling.
    ///
    /// Currently runs idempotence + commutativity + associativity (per
    /// summary), round-trip (per pair produced by
    /// `FunctionPairing.candidates(in:)`), and identity-element (per pair
    /// produced by `IdentityElementPairing.candidates(in:identities:)`).
    /// Multiple templates are allowed to fire on the same function —
    /// overlap (e.g. `merge` matching both commutativity and
    /// associativity since they share the same curated naming list per
    /// v0.2 §5.2; or `add` matching idempotence + commutativity +
    /// associativity if the type pattern allows; or `merge` + `IntSet.empty`
    /// triggering identity-element on top of the binary-op suggestions)
    /// is left for the M7 algebraic-structure-composition (§5.4) cluster
    /// to deduplicate.
    ///
    /// `typeDecls` feed M3.4's `ContradictionDetector` via
    /// `EquatableResolver` — commutativity suggestions whose return type
    /// classifies `.notEquatable` and round-trip pairs where either
    /// half's domain or codomain classifies `.notEquatable` get dropped
    /// per PRD §5.6 contradictions #2 / #3. Defaults to empty so M1/M2
    /// call sites that don't yet thread type-decl info compile and run
    /// unchanged — empty `typeDecls` yields a resolver with no corpus
    /// evidence, which only drops on the curated non-Equatable shape
    /// list (function types, `Any`, `AnyObject`, opaque/existential
    /// prefixes); concrete corpus types stay `.unknown` and survive.
    ///
    /// `diagnostic` is a stderr sink for the dropped-contradiction stream
    /// (M3 plan open decision #4 default `(b)`). Defaults to a no-op so
    /// non-CLI consumers (tests, programmatic discovery) don't spew
    /// diagnostics; the CLI's `Discover.run` wires it into the existing
    /// `DiagnosticOutput` channel so drops land on stderr alongside the
    /// vocabulary/config warning lines.
    ///
    /// `crossValidationFromTestLifter` is the M3.5 dormant seam for the
    /// PRD §4.1 `+20` cross-validation signal. Suggestions whose
    /// `identity` appears in the set get rebuilt with an additional
    /// `Signal(kind: .crossValidation, weight: 20)` and a matching
    /// `whySuggested` line; other suggestions pass through unchanged.
    /// The set defaults to empty because TestLifter M1 hasn't shipped in
    /// SwiftProtocolLaws — when it does, that milestone wires the input.
    /// Cross-validation is applied *after* the contradiction pass on
    /// purpose: a suggestion the §5.6 detector dropped is structurally
    /// untestable, so cross-validation can't (and shouldn't) resurrect
    /// it.
    public static func discover(
        in summaries: [FunctionSummary],
        identities: [IdentityCandidate] = [],
        typeDecls: [TypeDecl] = [],
        vocabulary: Vocabulary = .empty,
        diagnostic: (String) -> Void = { _ in },
        crossValidationFromTestLifter: Set<SuggestionIdentity> = []
    ) -> [Suggestion] {
        // M8.1 — InversePairTemplate needs the resolver to gate on
        // `.equatable`, so it's built before `collectSuggestions` and
        // threaded through. ContradictionDetector consumes the same
        // resolver downstream; one construction covers both passes.
        let resolver = EquatableResolver(typeDecls: typeDecls)
        let collector = collectSuggestions(
            summaries: summaries,
            identities: identities,
            vocabulary: vocabulary,
            equatableResolver: resolver
        )
        let outcome = ContradictionDetector.filter(
            collector.suggestions,
            typesToCheck: collector.contradictionTypes,
            resolver: resolver
        )
        for drop in outcome.dropped {
            diagnostic("contradiction: " + drop.reason)
        }
        let shapesByName = Dictionary(
            uniqueKeysWithValues: TypeShapeBuilder.shapes(from: typeDecls).map { ($0.name, $0) }
        )
        let withGenerators = GeneratorSelection.apply(
            to: outcome.kept,
            generatorTypeByIdentity: collector.generatorTypes,
            shapesByName: shapesByName
        )
        let crossValidated = applyCrossValidation(
            to: withGenerators,
            matching: crossValidationFromTestLifter
        )
        return crossValidated.sorted(by: lessThan)
    }

    /// Mutable accumulator used inside `collectSuggestions`. Keeps the
    /// three parallel collections in one place so the per-summary /
    /// per-pair helpers don't have to thread three `inout` parameters
    /// each. `contradictionTypes` feeds the M3.4 detector;
    /// `generatorTypes` feeds the M4.2 selector. Both are sparse —
    /// only suggestions that need per-suggestion type context are
    /// recorded.
    private struct SuggestionCollector {
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

    /// Run every shipped template against `summaries` + `identities`
    /// and bundle the resulting suggestions with their per-identity
    /// type context. Pulled out of `discover` so the orchestration
    /// function stays readable as a five-step pipeline (collect →
    /// drop → select generator → cross-validate → sort).
    private static func collectSuggestions(
        summaries: [FunctionSummary],
        identities: [IdentityCandidate],
        vocabulary: Vocabulary,
        equatableResolver: EquatableResolver
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
        var collector = SuggestionCollector()
        for summary in summaries {
            collectPerSummarySuggestions(
                summary: summary,
                vocabulary: vocabulary,
                reducerOps: reducerOps,
                into: &collector
            )
        }
        for pair in FunctionPairing.candidates(in: summaries) {
            if let suggestion = RoundTripTemplate.suggest(for: pair, vocabulary: vocabulary) {
                collector.record(
                    suggestion,
                    contradictionTypes: roundTripTypes(for: pair),
                    generatorType: generatorType(for: pair)
                )
            }
            // M8.1 — InversePairTemplate. Same `FunctionPair` input as
            // RoundTrip; gates internally on `EquatableResolver` so
            // Equatable T defers to RoundTrip and only `.notEquatable`
            // / `.unknown` fire here. No `contradictionTypes` plumbed —
            // ContradictionDetector would otherwise drop the very
            // suggestions this template is designed to surface.
            if let suggestion = InversePairTemplate.suggest(
                for: pair,
                vocabulary: vocabulary,
                equatableResolver: equatableResolver
            ) {
                collector.record(suggestion, generatorType: generatorType(for: pair))
            }
        }
        for pair in IdentityElementPairing.candidates(in: summaries, identities: identities) {
            if let suggestion = IdentityElementTemplate.suggest(
                for: pair,
                opsWithIdentitySeed: opsWithIdentitySeed
            ) {
                collector.record(suggestion, generatorType: generatorType(for: pair.operation))
            }
        }
        return collector
    }

    /// Idempotence + commutativity + associativity all fire per
    /// summary; this helper keeps the per-summary loop body readable
    /// by encapsulating the three constructions in one place.
    private static func collectPerSummarySuggestions(
        summary: FunctionSummary,
        vocabulary: Vocabulary,
        reducerOps: Set<String>,
        into collector: inout SuggestionCollector
    ) {
        let summaryGenType = generatorType(for: summary)
        if let suggestion = IdempotenceTemplate.suggest(for: summary, vocabulary: vocabulary) {
            collector.record(suggestion, generatorType: summaryGenType)
        }
        if let suggestion = CommutativityTemplate.suggest(for: summary, vocabulary: vocabulary) {
            collector.record(
                suggestion,
                contradictionTypes: commutativityTypes(for: summary),
                generatorType: summaryGenType
            )
        }
        if let suggestion = AssociativityTemplate.suggest(
            for: summary,
            vocabulary: vocabulary,
            reducerOps: reducerOps
        ) {
            collector.record(suggestion, generatorType: summaryGenType)
        }
        if let suggestion = MonotonicityTemplate.suggest(for: summary, vocabulary: vocabulary) {
            collector.record(suggestion, generatorType: summaryGenType)
        }
        if let suggestion = InvariantPreservationTemplate.suggest(for: summary) {
            collector.record(suggestion, generatorType: summaryGenType)
        }
    }

    /// Convenience: scan `directory` recursively, run every shipped
    /// template against the resulting summaries + identity candidates,
    /// and filter out any suggestion whose identity matches a
    /// `// swiftinfer: skip <hash>` marker found anywhere in the scanned
    /// `.swift` files (PRD §7.5). Uses `FunctionScanner.scanCorpus` so
    /// summaries, identity candidates, and `TypeDecl` records all come
    /// from a single AST walk — keeps the §13 perf budget intact even
    /// with the M3.4 contradiction pass active.
    public static func discover(
        in directory: URL,
        vocabulary: Vocabulary = .empty,
        diagnostic: (String) -> Void = { _ in },
        crossValidationFromTestLifter: Set<SuggestionIdentity> = []
    ) throws -> [Suggestion] {
        try discoverArtifacts(
            in: directory,
            vocabulary: vocabulary,
            diagnostic: diagnostic,
            crossValidationFromTestLifter: crossValidationFromTestLifter
        ).suggestions
    }

    /// Result of a `discoverArtifacts(in:)` run — bundles the surviving
    /// suggestions with the inverse-element witness records M8.4.a's
    /// `RefactorBridgeOrchestrator` needs to emit Group claims. M7.5
    /// callers continue to use `discover(in:)` for the suggestions-only
    /// shape; the M8.4.a CLI uses `discoverArtifacts` so it can thread
    /// the inverse pairs into the orchestrator without a second corpus
    /// scan.
    public struct DiscoverArtifacts: Sendable {
        public let suggestions: [Suggestion]
        public let inverseElementPairs: [InverseElementPair]

        public init(
            suggestions: [Suggestion],
            inverseElementPairs: [InverseElementPair]
        ) {
            self.suggestions = suggestions
            self.inverseElementPairs = inverseElementPairs
        }
    }

    /// Scan + discover + extract M8.3's inverse-element witnesses in one
    /// pass over the corpus. Mirrors `discover(in:)`'s semantics for
    /// suggestions (skip-marker filtering, every shipped template fires)
    /// and additionally returns `InverseElementPair` records the CLI
    /// threads into the M8.4.a orchestrator. The corpus is scanned
    /// exactly once — the inverse-element pass reads the same
    /// `corpus.summaries` array the suggestion-collection pass does, so
    /// the §13 perf budget isn't doubled.
    public static func discoverArtifacts(
        in directory: URL,
        vocabulary: Vocabulary = .empty,
        diagnostic: (String) -> Void = { _ in },
        crossValidationFromTestLifter: Set<SuggestionIdentity> = []
    ) throws -> DiscoverArtifacts {
        let corpus = try FunctionScanner.scanCorpus(directory: directory)
        let skipHashes = try SkipMarkerScanner.skipHashes(in: directory)
        let suggestions = discover(
            in: corpus.summaries,
            identities: corpus.identities,
            typeDecls: corpus.typeDecls,
            vocabulary: vocabulary,
            diagnostic: diagnostic,
            crossValidationFromTestLifter: crossValidationFromTestLifter
        ).filter { suggestion in
            !skipHashes.contains(suggestion.identity.normalized)
        }
        let inverseElementPairs = InverseElementPairing.candidates(
            in: corpus.summaries,
            vocabulary: vocabulary
        )
        return DiscoverArtifacts(
            suggestions: suggestions,
            inverseElementPairs: inverseElementPairs
        )
    }

    /// PRD §5.6 #2 — every type that has to classify Equatable for the
    /// commutativity suggestion to be testable. The type pattern guard
    /// in `CommutativityTemplate` enforces param[0] == param[1] ==
    /// return, but the detector is robust to template-side changes by
    /// listing all three.
    private static func commutativityTypes(for summary: FunctionSummary) -> [String] {
        var types = summary.parameters.map(\.typeText)
        if let returnType = summary.returnTypeText {
            types.append(returnType)
        }
        return types
    }

    /// Generator-relevant `T` for a single-summary template
    /// (idempotence's `T -> T`, commutativity / associativity /
    /// identity-element's `(T, T) -> T`). All four templates take their
    /// generator from the first parameter's type text — the type the
    /// emitted property test would generate values of. Returns `nil`
    /// for the (impossible-in-the-current-template-set) case of an
    /// arity-zero summary.
    private static func generatorType(for summary: FunctionSummary) -> String? {
        summary.parameters.first?.typeText
    }

    /// Generator-relevant `T` for the round-trip template. Picks the
    /// forward half's parameter type — the test sampled from `T`
    /// then asserts `g(f(t)) == t`, matching the
    /// `FunctionPairing.forward` orientation `RoundTripTemplate`
    /// already uses for evidence rendering.
    private static func generatorType(for pair: FunctionPair) -> String? {
        pair.forward.parameters.first?.typeText
    }

    /// PRD §5.6 #3 — domain and codomain on both halves of the
    /// round-trip pair. `FunctionPairing` enforces
    /// `forward.return == reverse.param[0]` and vice-versa, so the
    /// resulting set is at most two distinct type texts (T and U); the
    /// detector lists all four positions for symmetry with the
    /// commutativity helper.
    private static func roundTripTypes(for pair: FunctionPair) -> [String] {
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

    /// Detail text rendered for the M3.5 cross-validation signal. Kept
    /// generic for the dormant seam — once TestLifter M1 ships, the
    /// caller-side hook can pass a richer detail (e.g. the test name).
    static let crossValidationDetail = "Cross-validated by TestLifter"

    /// Walk `suggestions` and rebuild any whose `identity` is in
    /// `identities`, appending a `+20` cross-validation signal and a
    /// matching `whySuggested` line. Suggestions outside the set pass
    /// through by reference equality. The set is checked first so the
    /// fast path (empty set, no cross-validation) is a no-op.
    private static func applyCrossValidation(
        to suggestions: [Suggestion],
        matching identities: Set<SuggestionIdentity>
    ) -> [Suggestion] {
        if identities.isEmpty {
            return suggestions
        }
        return suggestions.map { suggestion in
            guard identities.contains(suggestion.identity) else {
                return suggestion
            }
            return rebuildWithCrossValidation(suggestion)
        }
    }

    private static func rebuildWithCrossValidation(_ suggestion: Suggestion) -> Suggestion {
        let signal = Signal(
            kind: .crossValidation,
            weight: 20,
            detail: crossValidationDetail
        )
        let newScore = Score(signals: suggestion.score.signals + [signal])
        let newWhy = suggestion.explainability.whySuggested + [signal.formattedLine]
        let newExplainability = ExplainabilityBlock(
            whySuggested: newWhy,
            whyMightBeWrong: suggestion.explainability.whyMightBeWrong
        )
        return Suggestion(
            templateName: suggestion.templateName,
            evidence: suggestion.evidence,
            score: newScore,
            generator: suggestion.generator,
            explainability: newExplainability,
            identity: suggestion.identity
        )
    }

    private static func lessThan(_ lhs: Suggestion, _ rhs: Suggestion) -> Bool {
        let lhsLoc = lhs.evidence.first?.location
        let rhsLoc = rhs.evidence.first?.location
        guard let lhsLoc, let rhsLoc else {
            return lhs.templateName < rhs.templateName
        }
        if lhsLoc.file != rhsLoc.file {
            return lhsLoc.file < rhsLoc.file
        }
        if lhsLoc.line != rhsLoc.line {
            return lhsLoc.line < rhsLoc.line
        }
        return lhs.templateName < rhs.templateName
    }
}
// swiftlint:enable file_length type_body_length
