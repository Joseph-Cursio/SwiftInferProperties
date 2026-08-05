import Foundation
import PropertyLawCore
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter

/// `PipelineResult` — everything one `discover` pass produced, in one record.
///
/// Split out of `Discover+Pipeline.swift` when that file crossed SwiftLint's 400-line cap
/// on 2026-08-01. The struct is the natural seam: it is a pure data record with no
/// behaviour, so moving it leaves the pipeline file a list of stages and nothing else.
extension SwiftInferCommand.Discover {

    /// Tier-filtered + config-aware suggestion collection. Shared
    /// by `Discover.run` (renderer / interactive / update-baseline)
    /// and `DriftCommand.run` (M6.5) so the two subcommands stay
    /// in lockstep — anything `discover` would surface is what
    /// `drift` diffs against the baseline.
    public struct PipelineResult {
        /// `var` so `replacingSuggestions(_:)` can narrow the set without rebuilding all
        /// fifteen stored properties — value semantics are unchanged.
        public var suggestions: [Suggestion]
        public let packageRoot: URL?

        /// Refutable laws the tier cut hid — see `VisibilityCut`. Consumed by the final-answer
        /// guard in `focus(_:with:diagnostics:)`, which is the only stage that can see whether
        /// hiding them left the reader with an honest empty or a confident pile of tautologies.
        public let tierHiddenRefutableLaws: [Suggestion]

        /// Inverse-element witness pairs (M8.3) — feeds M8.4.a's
        /// `RefactorBridgeOrchestrator.proposals(from:inverseElementPairs:)`
        /// to surface `Group` conformance proposals when the corpus
        /// has a unary inverse function alongside a binary op +
        /// identity element on the same type. Empty for the non-
        /// interactive code paths (drift, render-only); the
        /// orchestrator only consumes them in `--interactive` mode.
        public let inverseElementPairs: [InverseElementPair]

        /// M11.2 — equivalence-class hints keyed by the promoted
        /// suggestion's identity. Threaded through to
        /// `InteractiveTriage.Context.equivalenceClassHintsByIdentity`
        /// so the accept-flow renderer (M11.2d) can reach the hint
        /// without paying a per-suggestion storage cost on every
        /// `Suggestion` instance (the §13 row 4 memory ceiling rule).
        public let equivalenceClassHintsByIdentity: [SuggestionIdentity: EquivalenceClassHintKind]

        /// M16.3 — consumer-producer chain hints keyed by the promoted
        /// suggestion's identity. Same §13-row-4 out-of-band carrier
        /// posture as `equivalenceClassHintsByIdentity`; the M16.3
        /// accept-flow renderer reads this map by identity to reach
        /// the `DomainHint` for the writeout.
        public let consumerProducerChainHintsByIdentity: [SuggestionIdentity: DomainHint]

        /// V1.47.C — type declarations the discover pass saw, keyed by
        /// bare type name (no generic argument list). `IndexCommand`
        /// reads this to populate `SemanticIndexEntry.typeShape` so the
        /// verify pipeline can call `DerivationStrategist.strategy(for:)`
        /// without re-parsing the user's source. Empty for code paths
        /// that don't need it (the renderer / interactive flows).
        public let typeShapesByName: [String: PropertyLawCore.TypeShape]

        /// Conformances keyed by type name, with **cross-file extension records merged**
        /// (`ProtocolCoverageMap.inheritedTypesIndex`). Distinct from
        /// `typeShapesByName[...].inheritedTypes`, which `TypeShapeBuilder` merges from the
        /// primary decl and SAME-FILE extensions only. The difference is the whole ballgame
        /// on idiomatic third-party code: swift-collections writes `public struct BitSet {}`
        /// with a bare inheritance clause and declares all eleven conformances in separate
        /// `BitSet+X.swift` files, so the shape-derived map sees none of them.
        public let inheritedTypesByName: [String: Set<String>]

        /// Generic parameters per type name, for callers that must NAME a carrier in emitted
        /// source. `TypeShape` does not carry them and `TypeDecl.name` is the bare
        /// identifier, so before 2026-08-02 a generic carrier was indistinguishable from a
        /// concrete one at emission — which is why `scaffold-kit-suites` wrote `Deque.self`.
        public let genericParametersByName: [String: [TypeDecl.GenericParameter]]

        /// The file each type is **declared** in, keyed by bare type name.
        ///
        /// Third sidecar map, and here for the same reason as the two above: `TypeShape` belongs
        /// to SwiftPropertyLaws and has no use for a source path, so putting one on it would be a
        /// cross-repo change plus a pin bump.
        ///
        /// What it is for: verify's stub `@testable`-imports the module the *function* lives in,
        /// which is not enough. A law over `f(_ s: FunctionSummary)` names a type from another
        /// module, and `@testable import` does not re-export — so the stub cannot see it and the
        /// build fails. Measured 2026-08-03: **37 of 126** `predicate` entries failed exactly
        /// this way, 31 of them on `FunctionSummary` alone. A path resolves to a module through
        /// `VerifyTargetInference.module(forLocation:)`, so this map is the missing half of a
        /// mechanism that already exists.
        ///
        /// Populated from **declarations only** — see `sourceFileIndex` for why an extension
        /// must not vote.
        public let sourceFileByTypeName: [String: String]

        /// Generators synthesized from how the tests construct each type
        /// (mock-synthesis over the full construction record), keyed by type
        /// name — for *any* test-constructed type, not only suggestion-bearing
        /// ones. The scaffold pass uses these to fill holes structure can't.
        public let mockGeneratorsByType: [String: MockGenerator]

        /// Every function the discover pass scanned. Surfaced so the
        /// `--seeds` path can synthesize generic laws (e.g. determinism) for a
        /// seeded function that no signature-pattern template matched — the
        /// seed (lint evidence of purity) is what justifies the law, so it
        /// lives outside the template engine.
        public let summaries: [FunctionSummary]

        /// Functions the scan set aside as uncallable from an external test. Consulted only when
        /// a seed names one.
        public let restrictedFunctions: [RestrictedFunction]

        /// Effective `--docstring-advice` setting, resolved CLI > config > default (on).
        /// Surfaced here because the advisory is rendered by `Discover.run`, after the
        /// pipeline has already loaded the config — this saves a second `ConfigLoader.load`.
        public let docstringAdvice: Bool

        /// **What PropertyLawKit covers on this corpus** — rendered beside the suggestion
        /// count, never on its own.
        ///
        /// A `discover` count read alone is close to meaningless: if the kit were perfect
        /// there would be nothing left to discover, and the tool would report total success
        /// as `0 suggestions.` It rides on the result rather than being recomputed by the
        /// renderer so that no path can render suggestions without it. See `CoverageHeadline`.
        public let coverage: CoverageSummary

        public init(
            suggestions: [Suggestion],
            packageRoot: URL?,
            tierHiddenRefutableLaws: [Suggestion] = [],
            inverseElementPairs: [InverseElementPair] = [],
            equivalenceClassHintsByIdentity: [SuggestionIdentity: EquivalenceClassHintKind] = [:],
            consumerProducerChainHintsByIdentity: [SuggestionIdentity: DomainHint] = [:],
            typeShapesByName: [String: PropertyLawCore.TypeShape] = [:],
            inheritedTypesByName: [String: Set<String>] = [:],
            genericParametersByName: [String: [TypeDecl.GenericParameter]] = [:],
            sourceFileByTypeName: [String: String] = [:],
            mockGeneratorsByType: [String: MockGenerator] = [:],
            summaries: [FunctionSummary] = [],
            restrictedFunctions: [RestrictedFunction] = [],
            docstringAdvice: Bool,
            // Defaulted so the many test-side constructions of a PipelineResult stay
            // compiling. The discover path always passes a computed summary — the default
            // is "nothing was audited", which renders an honest zero rather than a silence.
            coverage: CoverageSummary = CoverageSummary(
                lawCount: 0, carrierCount: 0, evidenceState: .noEvidence
            )
        ) {
            self.suggestions = suggestions
            self.packageRoot = packageRoot
            self.tierHiddenRefutableLaws = tierHiddenRefutableLaws
            self.inverseElementPairs = inverseElementPairs
            self.equivalenceClassHintsByIdentity = equivalenceClassHintsByIdentity
            self.consumerProducerChainHintsByIdentity = consumerProducerChainHintsByIdentity
            self.typeShapesByName = typeShapesByName
            self.inheritedTypesByName = inheritedTypesByName
            self.genericParametersByName = genericParametersByName
            self.sourceFileByTypeName = sourceFileByTypeName
            self.mockGeneratorsByType = mockGeneratorsByType
            self.summaries = summaries
            self.restrictedFunctions = restrictedFunctions
            self.docstringAdvice = docstringAdvice
            self.coverage = coverage
        }

        /// The same result with a narrowed suggestion set.
        ///
        /// **The shape maps are deliberately NOT narrowed.** `verify` resolves generators over
        /// the whole scanned type universe, so filtering `typeShapesByName` alongside the
        /// suggestions would manufacture carrier declines for types that are present — the
        /// failure `allShapes` threading was added to prevent, and which a census once
        /// misattributed two-thirds of a carrier problem to.
        public func replacingSuggestions(_ suggestions: [Suggestion]) -> Self {
            var copy = self
            copy.suggestions = suggestions
            return copy
        }
    }
}
