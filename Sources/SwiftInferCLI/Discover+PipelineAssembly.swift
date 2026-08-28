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

    /// Whether `@testable import` can NAME each type, keyed the same way the two maps above
    /// are keyed.
    ///
    /// **Only `false` entries are recorded.** An absent key means *not known to be file-scoped*,
    /// which is what every caller predating this map assumed for everything, so a consumer that
    /// does not find a type behaves exactly as before. Recording `true` for the majority would
    /// make the map large and say nothing.
    ///
    /// **First-wins on collision, matching `genericParametersIndex`.** Two same-named types in
    /// different namespaces are a known hazard of bare-name keying here; recording the first is
    /// the conservative direction for THIS consumer, since the alternative — a later `public`
    /// namesake overwriting an earlier `private` one — would re-admit the carrier this exists to
    /// block.
    static func visibleToTestableImportIndex(from typeDecls: [TypeDecl]) -> [String: Bool] {
        var index: [String: Bool] = [:]
        for decl in typeDecls where !decl.isVisibleToTestableImport {
            let key = ProtocolCoverageMap.strippingGenericParameters(decl.name)
            if index[key] == nil { index[key] = false }
        }
        return index
    }

    /// Where each type is **declared**, keyed by bare name — the fact verify needs to work out
    /// which module to import, and the third sidecar map after `inheritedTypesByName` and
    /// `genericParametersByName`.
    ///
    /// It is a sidecar rather than a field on the shape because `typeShapesByName` holds
    /// `PropertyLawCore.TypeShape`, which belongs to **SwiftPropertyLaws**. Carrying a source
    /// path on it would be a cross-repo change plus a pin bump, for a fact the kit has no use
    /// for. `genericParametersByName` exists for exactly this reason and says so.
    ///
    /// **Extensions do not vote, and that is the whole rule.** A declaration tells you where a
    /// type *lives*; an extension only tells you where somebody *reached* it. This repo writes
    /// `extension String` in `SwiftInferCore`, and letting that count would attribute `String`
    /// to `SwiftInferCore` — a module that does not define it. The consequence is not a stray
    /// import but a wrong one: the stub would name a module for a stdlib type and stop looking.
    ///
    /// Ties among genuine declarations keep the first seen, matching
    /// `genericParametersIndex`. Two modules declaring the same type name collide — an existing
    /// limitation of `typeShapesByName`, which is keyed the same way, inherited here rather
    /// than introduced.
    static func sourceFileIndex(from typeDecls: [TypeDecl]) -> [String: String] {
        var index: [String: String] = [:]
        for decl in typeDecls where decl.kind != .extension {
            let key = ProtocolCoverageMap.strippingGenericParameters(decl.name)
            if index[key] == nil { index[key] = decl.location.file }
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
                restrictedFunctions: artifacts.restrictedFunctions,
                summaries: artifacts.summaries
            ),
            packageRoot: setup.packageRoot,
            tierHiddenRefutableLaws: cut.hiddenRefutable,
            refutedLaws: cut.refuted,
            inverseElementPairs: artifacts.inverseElementPairs,
            equivalenceClassHintsByIdentity: hints.equivalenceClassHints,
            consumerProducerChainHintsByIdentity: hints.chainHints,
            typeShapesByName: hints.typeShapesByName,
            inheritedTypesByName: ProtocolCoverageMap.inheritedTypesIndex(from: artifacts.typeDecls),
            genericParametersByName: genericParametersIndex(from: artifacts.typeDecls),
            visibleToTestableImportByName: visibleToTestableImportIndex(from: artifacts.typeDecls),
            sourceFileByTypeName: sourceFileIndex(from: artifacts.typeDecls),
            mockGeneratorsByType: synthesizeMockGenerators(from: liftedArtifacts.constructionRecord),
            summaries: artifacts.summaries,
            restrictedFunctions: artifacts.restrictedFunctions,
            docstringAdvice: setup.docstringAdvice,
            coverage: cut.coverage
        )
    }
}
