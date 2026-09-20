import Foundation
import PropertyLawCore
import SwiftInferCore
import SwiftInferTemplates

/// The triage dependencies `InteractiveTriage` threads through its accept path.
///
/// Extracted from `InteractiveTriage.swift` when that file reached SwiftLint's 400-line cap. The
/// type is one bundle of stored properties and their reasoning, which is a clean seam: nothing
/// here decides anything, and every consumer takes the whole `Context`.
extension InteractiveTriage {

    /// Bundle of triage dependencies — keeps `run`'s parameter list
    /// short and lets sub-helpers share the same set without
    /// re-threading individual deps. SwiftLint also caps function
    /// parameter counts at 5; bundling keeps both `run` and
    /// `handleAccept` under that limit.
    public struct Context {
        public let prompt: any PromptInput
        public let output: any DiscoverOutput
        public let diagnostics: any DiagnosticOutput
        public let outputDirectory: URL

        /// The directory holding `SwiftInfer/` and `SwiftInferRefactors/`.
        ///
        /// Was `outputDirectory/Tests/Generated` at every accept site, hard-coded — a path
        /// **no SwiftPM target builds on any package** (#414). `GeneratedStubDestination`
        /// resolves it from the manifest; this defaults to the old value so callers that
        /// cannot resolve one (unit fixtures with no `Package.swift`) behave exactly as
        /// before.
        public let generatedRoot: URL

        public let dryRun: Bool
        public let clock: @Sendable () -> Date
        /// Per-type RefactorBridge proposals keyed by type name, built
        /// by `RefactorBridgeOrchestrator.proposals(from:)` (M7.5b +
        /// M8.4.b.1). Each value is a list — M7.5 emitted a single
        /// proposal per type; M8.4.b.1 widens to list-shaped for
        /// incomparable arms (CommutativeMonoid + Group on the same
        /// type) and primary/secondary pairs (Semilattice + SetAlgebra
        /// when curated set-named ops fire). The prompt loop renders
        /// position 0 as `B` and position 1 as `B'` in the extended
        /// `[A/B/B'/s/n/?]` prompt.
        ///
        /// Empty when the caller didn't run the orchestrator (M5.x and
        /// earlier non-CLI consumers); the prompt loop falls back to
        /// the M6.4 `[A/s/n/?]` shape when no proposal matches.
        public let proposalsByType: [String: [RefactorBridgeProposal]]

        /// M11.2 — equivalence-class hints keyed by the promoted
        /// suggestion's identity. Carried out-of-band on the Context
        /// (rather than inline on `Suggestion`) so the per-instance
        /// suggestion size stays unchanged — the §13 row 4 memory
        /// ceiling regression test caught a 65MB delta when the hint
        /// was inlined as an optional struct field on every Suggestion
        /// (each TemplateEngine suggestion paid the optional's storage
        /// even when nil; the corpus has thousands of suggestions and
        /// many transient copies during pipeline). The side-map shape
        /// trades one hash lookup at accept-flow time for a flat
        /// allocation profile.
        ///
        /// Empty when the caller isn't running the M11.1 detector pass
        /// (M11.0 / M5.x callers) — the M11.2 accept-flow falls back
        /// to a no-op writeout in that case.
        public let equivalenceClassHintsByIdentity: [SuggestionIdentity: EquivalenceClassHintKind]

        /// TestLifter M16.3 — consumer-producer chain `DomainHint`s
        /// keyed by promoted suggestion identity, carried out-of-band
        /// for the same §13 row 4 reason as `equivalenceClassHintsByIdentity`
        /// (avoids inflating `Suggestion`'s per-instance storage with
        /// an optional that's nil for every TemplateEngine suggestion).
        /// Empty when the caller isn't running the M16.1 detector;
        /// the M16.3 accept-flow falls back to a no-op writeout in
        /// that case.
        public let consumerProducerChainHintsByIdentity: [SuggestionIdentity: DomainHint]

        /// V1.68 — persisted `swift-infer verify` evidence keyed by
        /// `SuggestionIdentity.normalized`, the same map `discover`
        /// threads into the renderer for verified-first ordering. Used
        /// at decision-record time so `DecisionRecord.tier` carries the
        /// *effective* tier — a `.strong` pick with `.measuredBothPass`
        /// evidence records as `.verified`, not `.strong` — and the
        /// `metrics` tier-mix reflects it. Empty when the caller didn't
        /// load evidence (non-`discover` callers); `makeRecord` then
        /// records the base score-derived tier unchanged.
        public let verifyEvidenceByIdentity: [String: VerifyEvidence]

        /// Parsed shapes of the project's types, keyed by name — the input the
        /// accept flow's `GeneratorResolver` derives custom-type generators from,
        /// so an emitted stub over a project struct/enum compiles without a
        /// hand-written `gen()`. Empty for callers that don't supply it
        /// (generators then fall back to `Type.gen()`).
        public let typeShapesByName: [String: TypeShape]

        /// The module an emitted stub must `@testable import` to name its subject, resolved
        /// once per run from the manifest.
        ///
        /// The per-file `Sources/<Module>/` heuristic is tried first and answers for a
        /// conventional package. It cannot answer for an Xcode-originated layout —
        /// `SwiftMarkdownWiki/Editor/EditorFormatter.swift` has no `Sources/` component — which
        /// is precisely the case `--sources` exists to serve, and the import was being dropped
        /// there with no diagnostic: 0 of 19 emitted stubs named the module under test (#415).
        ///
        /// `nil` for a caller with no manifest to read, which is every unit fixture. The stub
        /// then carries a to-do line naming what is missing rather than silently omitting it.
        public let moduleUnderTest: String?

        /// Each scanned type's generic parameters, so the accept path can tell a type parameter
        /// from a type. `Discover+PipelineAssembly` already builds this for
        /// `scaffold-kit-suites` and dropped it before the stub writer (#493).
        public let genericParametersByName: [String: [TypeDecl.GenericParameter]]
        /// Where each scanned type is declared, and the package those files sit in — the two
        /// maps `VerifyImportSet` needs to turn a carrier's reachable types into imports.
        ///
        /// Discover already builds `sourceFileByTypeName` (`Discover.sourceFileIndex(from:)`)
        /// and dropped it before the stub writer, which is why the accept path could not answer
        /// a question the verify path had answered since 2026-08-03 (#492).
        public let sourceFileByTypeName: [String: String]

        /// Every scanned type's conformances, merged across files and extensions — the index
        /// `scaffold-kit-suites` already reads. The accept path uses it to tell whether a
        /// `monotonicity` carrier can be ordered at all (`UnorderedCarrierGate`).
        public let inheritedTypesByName: [String: Set<String>]

        /// Generators for SwiftSyntax node parameters, from snippets the package's tests parse.
        /// `nil` for every caller that does not supply one, which keeps the explained `.todo`.
        /// Set after construction because the type is internal and the initializer is public.
        var syntaxCorpus: SyntaxCorpusSource?

        /// Generators for a class receiver, built as the package's own tests build it. `nil` for
        /// every caller that does not supply one, which keeps the explained `.todo`.
        var receiverConstructions: ReceiverConstructionSource?

        /// `nil` for a caller with no package on disk, which is every unit fixture; carrier
        /// imports are then not resolved and the stub emits what it did before.
        public let packageRoot: URL?

        public init(
            prompt: any PromptInput,
            output: any DiscoverOutput,
            diagnostics: any DiagnosticOutput,
            outputDirectory: URL,
            generatedRoot: URL? = nil,
            dryRun: Bool,
            clock: @escaping @Sendable () -> Date = { Date() },
            proposalsByType: [String: [RefactorBridgeProposal]] = [:],
            equivalenceClassHintsByIdentity: [SuggestionIdentity: EquivalenceClassHintKind] = [:],
            consumerProducerChainHintsByIdentity: [SuggestionIdentity: DomainHint] = [:],
            verifyEvidenceByIdentity: [String: VerifyEvidence] = [:],
            typeShapesByName: [String: TypeShape] = [:],
            moduleUnderTest: String? = nil,
            genericParametersByName: [String: [TypeDecl.GenericParameter]] = [:],
            sourceFileByTypeName: [String: String] = [:],
            inheritedTypesByName: [String: Set<String>] = [:],
            packageRoot: URL? = nil
        ) {
            self.prompt = prompt
            self.output = output
            self.diagnostics = diagnostics
            self.outputDirectory = outputDirectory
            self.generatedRoot = generatedRoot
                ?? GeneratedStubDestination.legacyRoot(packageRoot: outputDirectory)
            self.dryRun = dryRun
            self.clock = clock
            self.proposalsByType = proposalsByType
            self.equivalenceClassHintsByIdentity = equivalenceClassHintsByIdentity
            self.consumerProducerChainHintsByIdentity = consumerProducerChainHintsByIdentity
            self.verifyEvidenceByIdentity = verifyEvidenceByIdentity
            self.typeShapesByName = typeShapesByName
            self.moduleUnderTest = moduleUnderTest
            self.genericParametersByName = genericParametersByName
            self.sourceFileByTypeName = sourceFileByTypeName
            self.inheritedTypesByName = inheritedTypesByName
            self.packageRoot = packageRoot
        }
    }
}
