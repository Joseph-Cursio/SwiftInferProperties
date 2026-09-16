import Foundation
import SwiftInferCore

/// Split out of `SwiftInferTemplates.swift`, which reached SwiftLint's 400-line file cap when
/// `unmatchedSkipHashes` landed (#490). The type is the scan's whole output and has no reason
/// to live inside the file that happens to produce it.
public extension TemplateRegistry {

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

        /// `// swiftinfer: skip <hash>` markers in the scanned sources that matched no
        /// suggestion this run proposed, so they suppress nothing.
        ///
        /// Recorded here because this is the only place that sees both the markers and the
        /// unfiltered proposals. `DriftCommand` reports them and carries the reasoning (#490).
        public let unmatchedSkipHashes: Set<String>

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
            unmatchedSkipHashes: Set<String> = [],
            summaries: [FunctionSummary] = [],
            typeDecls: [TypeDecl] = [],
            effectAnnotations: [EffectAnnotationAdvice] = [],
            restrictedFunctions: [RestrictedFunction] = []
        ) {
            self.suggestions = suggestions
            self.inverseElementPairs = inverseElementPairs
            self.unmatchedSkipHashes = unmatchedSkipHashes
            self.summaries = summaries
            self.typeDecls = typeDecls
            self.effectAnnotations = effectAnnotations
            self.restrictedFunctions = restrictedFunctions
        }
    }
}
