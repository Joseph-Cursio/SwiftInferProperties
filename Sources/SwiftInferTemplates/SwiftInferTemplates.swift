import Foundation
import SwiftInferCore

/// SwiftInferTemplates — TemplateEngine template registry.
///
/// PRD §5.2 specifies eight shipped templates: round-trip,
/// idempotence, commutativity, associativity, monotonicity,
/// identity-element, invariant-preservation, inverse-pair. M1.3
/// shipped **idempotence**; M1.4 added **round-trip** + cross-function
/// pairing; M2.3 added **commutativity**; M2.4 added **associativity**
/// with reducer/builder usage as a new type-flow signal; M2.5 added
/// **identity-element** with op + identity constant cross-pairing and
/// an accumulator-with-empty-seed type-flow signal; subsequent
/// milestones added the remaining three.
public enum SwiftInferTemplates {}

/// Static registry that orchestrates every shipped template against a
/// corpus of `FunctionSummary` records. Kept in `SwiftInferTemplates`
/// (rather than the CLI) so the discovery pipeline is reachable from
/// tests without going through ArgumentParser, and so v1.1's
/// constraint-engine upgrade has a single seam to slot into.
///
/// The collection helpers (per-summary, per-pair, identity-element
/// pairing) live in `TemplateRegistry+Collection.swift`; the M3.5
/// cross-validation seam + final sort live in
/// `TemplateRegistry+CrossValidation.swift`.
public enum TemplateRegistry {

    /// Run every shipped template against `summaries`. Output is sorted
    /// by (file path, line) of the first evidence row so the byte-
    /// identical-reproducibility guarantee (PRD §16 #6) holds across
    /// runs.
    ///
    /// `vocabulary` is the project-extensible naming layer per PRD §4.5;
    /// templates consult it alongside their curated lists. Defaults to
    /// `.empty` so M1 call sites that haven't been updated for the M2
    /// vocabulary plumbing keep compiling.
    ///
    /// `typeDecls` feed M3.4's `ContradictionDetector` via
    /// `EquatableResolver` — commutativity suggestions whose return
    /// type classifies `.notEquatable` and round-trip pairs where
    /// either half's domain or codomain classifies `.notEquatable` get
    /// dropped per PRD §5.6 contradictions #2 / #3.
    ///
    /// `diagnostic` is a stderr sink for the dropped-contradiction
    /// stream (M3 plan open decision #4 default `(b)`).
    ///
    /// `crossValidationFromTestLifter` is the seam for the PRD §4.1
    /// `+20` cross-validation signal. Suggestions whose
    /// `crossValidationKey` appears in the set get rebuilt with an
    /// additional `Signal(kind: .crossValidation, weight: 20)` and a
    /// matching `whySuggested` line.
    ///
    /// **TestLifter M1.4 widened this from `Set<SuggestionIdentity>`
    /// to `Set<CrossValidationKey>`** because the full
    /// `SuggestionIdentity`'s signature/type info isn't recoverable
    /// from a test body — TestLifter has callee names but no
    /// resolved parameter / return types. The lighter-weight key
    /// captures the matchable surface (template + sorted callee
    /// names) without forcing semantic resolution.
    public static func discover(
        in summaries: [FunctionSummary],
        identities: [IdentityCandidate] = [],
        typeDecls: [TypeDecl] = [],
        vocabulary: Vocabulary = .empty,
        diagnostic: (String) -> Void = { _ in /* no-op */ },
        crossValidationFromTestLifter: Set<CrossValidationKey> = [],
        counterSignalsFromTestLifter: Set<CrossValidationKey> = [],
        templateFilter: Set<String>? = nil
    ) -> [Suggestion] {
        // M8.1 — InversePairTemplate needs the resolver to gate on
        // `.equatable`, so it's built before `collectSuggestions` and
        // threaded through. ContradictionDetector consumes the same
        // resolver downstream; one construction covers both passes.
        let resolver = EquatableResolver(typeDecls: typeDecls)
        // V1.5.2 — corpus-wide `name → union of inherited types` index
        // feeds the protocol-coverage veto across the six algebraic
        // templates. Built once here so per-summary template calls are
        // O(|inheritedTypes|) ≈ 1–4 lookups per candidate.
        let inheritedTypesByName = ProtocolCoverageMap.inheritedTypesIndex(from: typeDecls)
        // V1.18.A — corpus-wide carrier-kind resolver feeds the
        // value-semantic / reference-type carrier signals across the four
        // suggestion-emitting templates that score against a containing
        // type (Idempotence, RoundTrip, InversePair, IdentityElement).
        // Same single-build pattern as `EquatableResolver`.
        let carrierKindResolver = CarrierKindResolver(typeDecls: typeDecls)
        // V1.19.A — corpus-wide lifted-transformation set, derived once
        // from the mutating-func summaries that pass the strict
        // value-semantic carrier gate. Threaded into V1.19.B-D template
        // fan-out (Idempotence, IdentityElement, Composition, InversePair).
        // Same single-build pattern as the resolvers above.
        let liftedTransformations = LiftedTransformation.derive(
            from: summaries,
            carrierKindResolver: carrierKindResolver
        )
        let collector = collectSuggestions(
            summaries: summaries,
            identities: identities,
            vocabulary: vocabulary,
            equatableResolver: resolver,
            inheritedTypesByName: inheritedTypesByName,
            carrierKindResolver: carrierKindResolver,
            liftedTransformations: liftedTransformations,
            typeDecls: typeDecls
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
        // M5.4 — Codable round-trip fallback runs after the strategist
        // pass. The TemplateEngine main path doesn't run the M4 mock
        // fallback (mock-inferred is lifted-only per the M4.3 OD #2
        // narrowing), so here the Codable pass is the second of two
        // selection passes. Strategist-derived survivors are preserved
        // by the .notYetComputed guard inside the fallback.
        let withCodableFallback = GeneratorSelection.applyCodableRoundTripFallback(
            to: withGenerators,
            generatorTypeByIdentity: collector.generatorTypes,
            typeDecls: typeDecls
        )
        return finalizeSuggestions(
            withCodableFallback,
            crossValidation: crossValidationFromTestLifter,
            counterSignals: counterSignalsFromTestLifter,
            templateFilter: templateFilter
        )
    }

    /// V1.43 cleanup helper — extracted from `discover` to keep that
    /// function body within SwiftLint's `function_body_length` cap.
    /// Runs the three post-selection passes (cross-validation,
    /// counter-signal, template-filter) and the final sort. No
    /// behavior change.
    private static func finalizeSuggestions(
        _ suggestions: [Suggestion],
        crossValidation: Set<CrossValidationKey>,
        counterSignals: Set<CrossValidationKey>,
        templateFilter: Set<String>?
    ) -> [Suggestion] {
        let crossValidated = applyCrossValidation(to: suggestions, matching: crossValidation)
        // M7 counter-signal pass runs AFTER cross-validation (M7 plan
        // OD #5): suggestions both cross-validated AND counter-signaled
        // land at base+20-25 = base-5, preserving relative weighting.
        let counterSignaled = applyCounterSignal(to: crossValidated, matching: counterSignals)
        // V1.32.B Domain Template Packs (PRD §20.3) — applied AFTER the
        // signal passes so filtering doesn't alter their inputs. Nil
        // filter preserves the monolithic-registry behavior bit-for-bit.
        let filtered: [Suggestion]
        if let templateFilter {
            filtered = counterSignaled.filter { templateFilter.contains($0.templateName) }
        } else {
            filtered = counterSignaled
        }
        return sortSuggestions(filtered)
    }

    /// Convenience: scan `directory` recursively, run every shipped
    /// template against the resulting summaries + identity candidates,
    /// and filter out any suggestion whose identity matches a
    /// `// swiftinfer: skip <hash>` marker found anywhere in the
    /// scanned `.swift` files (PRD §7.5).
    public static func discover(
        in directory: URL,
        vocabulary: Vocabulary = .empty,
        diagnostic: (String) -> Void = { _ in /* no-op */ },
        crossValidationFromTestLifter: Set<CrossValidationKey> = [],
        counterSignalsFromTestLifter: Set<CrossValidationKey> = [],
        templateFilter: Set<String>? = nil
    ) throws -> [Suggestion] {
        try discoverArtifacts(
            in: directory,
            vocabulary: vocabulary,
            diagnostic: diagnostic,
            crossValidationFromTestLifter: crossValidationFromTestLifter,
            counterSignalsFromTestLifter: counterSignalsFromTestLifter,
            templateFilter: templateFilter
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

        /// `@lint.effect pure` advisory records — one per function the scan
        /// inferred referentially transparent (`SoundPurity`). A separate
        /// channel from `suggestions`: this is annotation advice, not a
        /// property-test candidate, so it never enters the templateName-driven
        /// accept / verify / decisions pipeline. Source-ordered.
        public let effectAnnotations: [EffectAnnotationAdvice]

        /// Function summaries the corpus scan produced. Exposed for
        /// TestLifter M3.2's `LiftedSuggestionRecovery` pass — the
        /// promoted lifted Suggestions need callee-type recovery from
        /// the same `[FunctionSummary]` index TemplateEngine consumed
        /// internally. Mirrors the M8.4.a `inverseElementPairs`
        /// widening pattern: expose the pre-discovery state CLI
        /// callers need to thread into downstream passes without a
        /// second corpus scan.
        public let summaries: [FunctionSummary]

        /// Type declarations the corpus scan produced. Exposed for the
        /// same M3.2 reason — the promoted lifted Suggestions go
        /// through `GeneratorSelection` in CLI, which needs the
        /// `[String: TypeShape]` index built from `typeDecls`.
        public let typeDecls: [TypeDecl]

        /// Functions the scan set aside as uncallable from an external test. A separate channel
        /// from `summaries` for the same reason `effectAnnotations` is: these are not
        /// property-test candidates by default and never enter the template pipeline. A **seed**
        /// naming one is an explicit request, though, and can rescue it — with the access caveat
        /// attached, so the reader learns what refactor unlocks the test.
        public let restrictedFunctions: [RestrictedFunction]

        public init(
            suggestions: [Suggestion],
            inverseElementPairs: [InverseElementPair],
            summaries: [FunctionSummary] = [],
            typeDecls: [TypeDecl] = [],
            effectAnnotations: [EffectAnnotationAdvice] = [],
            restrictedFunctions: [RestrictedFunction] = []
        ) {
            self.suggestions = suggestions
            self.inverseElementPairs = inverseElementPairs
            self.summaries = summaries
            self.typeDecls = typeDecls
            self.effectAnnotations = effectAnnotations
            self.restrictedFunctions = restrictedFunctions
        }
    }

    /// Scan + discover + extract M8.3's inverse-element witnesses in
    /// one pass over the corpus. Mirrors `discover(in:)`'s semantics
    /// for suggestions and additionally returns `InverseElementPair`
    /// records the CLI threads into the M8.4.a orchestrator.
    public static func discoverArtifacts(
        in directory: URL,
        vocabulary: Vocabulary = .empty,
        diagnostic: (String) -> Void = { _ in /* no-op */ },
        crossValidationFromTestLifter: Set<CrossValidationKey> = [],
        counterSignalsFromTestLifter: Set<CrossValidationKey> = [],
        templateFilter: Set<String>? = nil
    ) throws -> DiscoverArtifacts {
        let corpus = try FunctionScanner.scanCorpus(directory: directory)
        let skipHashes = try SkipMarkerScanner.skipHashes(in: directory)
        let suggestions = discover(
            in: corpus.summaries,
            identities: corpus.identities,
            typeDecls: corpus.typeDecls,
            vocabulary: vocabulary,
            diagnostic: diagnostic,
            crossValidationFromTestLifter: crossValidationFromTestLifter,
            counterSignalsFromTestLifter: counterSignalsFromTestLifter,
            templateFilter: templateFilter
        ).filter { suggestion in
            !skipHashes.contains(suggestion.identity.normalized)
        }
        let inverseElementPairs = InverseElementPairing.candidates(
            in: corpus.summaries,
            vocabulary: vocabulary
        )
        return DiscoverArtifacts(
            suggestions: suggestions,
            inverseElementPairs: inverseElementPairs,
            summaries: corpus.summaries,
            typeDecls: corpus.typeDecls,
            effectAnnotations: EffectAnnotationAdvice.adviceList(from: corpus.summaries),
            restrictedFunctions: corpus.restricted
        )
    }
}
