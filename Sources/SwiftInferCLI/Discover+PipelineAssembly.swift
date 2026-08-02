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

    /// Generic parameters keyed by the stripped type name, for callers that must NAME a
    /// carrier in emitted source. Keyed the same way `inheritedTypesIndex` keys, so the two
    /// look up together. Only generic decls are recorded; the map is empty for most corpora.
    static func genericParametersIndex(
        from typeDecls: [TypeDecl]
    ) -> [String: [TypeDecl.GenericParameter]] {
        var index: [String: [TypeDecl.GenericParameter]] = [:]
        for decl in typeDecls where !decl.genericParameters.isEmpty {
            let key = ProtocolCoverageMap.strippingGenericParameters(decl.name)
            if index[key] == nil { index[key] = decl.genericParameters }
        }
        return index
    }

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
            inheritedTypesByName: ProtocolCoverageMap.inheritedTypesIndex(from: artifacts.typeDecls),
            genericParametersByName: genericParametersIndex(from: artifacts.typeDecls),
            mockGeneratorsByType: synthesizeMockGenerators(from: liftedArtifacts.constructionRecord),
            summaries: artifacts.summaries,
            restrictedFunctions: artifacts.restrictedFunctions,
            docstringAdvice: setup.docstringAdvice,
            coverage: cut.coverage
        )
    }
}
