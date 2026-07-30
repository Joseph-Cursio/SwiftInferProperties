import Foundation
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter

/// Assembling a `PipelineResult` from the four things the discover pass produced.
///
/// Split out of `Discover+Pipeline.swift` for the reason its own header gives about the
/// file it was split from: `collectVisibleSuggestions` crossed SwiftLint's 50-line body
/// cap when the seed manifest started reaching the pipeline. Extracting the *assembly*
/// (as opposed to any of the stages) keeps that function a readable list of stages —
/// setup, lift, discover, cut, assemble — with the sixteen-field construction that used
/// to end it moved behind one call.
extension SwiftInferCommand.Discover {

    /// Build the result, applying the two corpus-dependent caveat passes on the way.
    ///
    /// Order matters and is not arbitrary: `withResolvedConformanceCaveats` *removes* lines
    /// the type declarations disprove, and `withAccessRestrictionCaveats` *prepends* the
    /// access remedy. Running the removal first means the remedy stays first in the final
    /// list, which is where a reader deciding whether to act on the suggestion will look.
    static func makePipelineResult(
        setup: PipelineSetup,
        artifacts: TemplateRegistry.DiscoverArtifacts,
        liftedArtifacts: TestLifter.Artifacts,
        cut: VisibilityCut,
        hints: HintsAndShapes
    ) -> PipelineResult {
        PipelineResult(
            suggestions: withAccessRestrictionCaveats(
                withResolvedConformanceCaveats(cut.visible, typeDecls: artifacts.typeDecls),
                restrictedFunctions: artifacts.restrictedFunctions
            ),
            packageRoot: setup.packageRoot,
            tierHiddenRefutableLaws: cut.hiddenRefutable,
            inverseElementPairs: artifacts.inverseElementPairs,
            equivalenceClassHintsByIdentity: hints.equivalenceClassHints,
            consumerProducerChainHintsByIdentity: hints.chainHints,
            typeShapesByName: hints.typeShapesByName,
            mockGeneratorsByType: synthesizeMockGenerators(from: liftedArtifacts.constructionRecord),
            summaries: artifacts.summaries,
            restrictedFunctions: artifacts.restrictedFunctions,
            docstringAdvice: setup.docstringAdvice
        )
    }
}
