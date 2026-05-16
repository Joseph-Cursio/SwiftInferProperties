import Foundation
import SwiftInferCore

/// V1.89 lint pass — commutativity + associativity stub-bundle
/// builders extracted from `VerifyCommand+TemplateDispatch.swift`
/// so the main dispatch file stays under SwiftLint's 400-line cap.
/// Same internal-static access as the round-trip / idempotence
/// builders that remain in the dispatch file.
extension SwiftInferCommand.Verify {

    static func commutativityStubBundle(
        entry: SemanticIndexEntry,
        budget: CommutativityStubEmitter.TrialBudget
    ) throws -> VerifyStubBundle {
        let resolved = try CommutativityPairResolver.resolve(entry)
        let source = try CommutativityStubEmitter.emit(
            CommutativityStubEmitter.Inputs(
                functionCall: resolved.functionCall,
                extraImports: [],
                carrierType: entry.typeName ?? "(none)",
                seedHex: makeSeedHex(from: entry.identityHash),
                trialBudget: budget
            )
        )
        // For commutativity, both `forwardName` and `inverseName` slots
        // hold the same single function call. The renderer's
        // `RenderShape.commutativity` reads it once and produces
        // `f(lhs, rhs)` and `f(rhs, lhs)` for the two value lines.
        let context = VerifyResultRenderer.Context(
            templateName: "commutativity",
            forwardName: resolved.functionCall,
            inverseName: resolved.functionCall,
            carrierType: entry.typeName ?? "(none)"
        )
        return VerifyStubBundle(source: source, rendererContext: context)
    }

    static func associativityStubBundle(
        entry: SemanticIndexEntry,
        budget: AssociativityStubEmitter.TrialBudget
    ) throws -> VerifyStubBundle {
        let resolved = try AssociativityPairResolver.resolve(entry)
        let source = try AssociativityStubEmitter.emit(
            AssociativityStubEmitter.Inputs(
                functionCall: resolved.functionCall,
                extraImports: [],
                carrierType: entry.typeName ?? "(none)",
                seedHex: makeSeedHex(from: entry.identityHash),
                trialBudget: budget
            )
        )
        // For associativity, both `forwardName` and `inverseName` slots
        // hold the same single function call. The renderer's
        // `RenderShape.associativity` reads it once and produces
        // `f(f(a, b), c)` and `f(a, f(b, c))` for the two value lines.
        let context = VerifyResultRenderer.Context(
            templateName: "associativity",
            forwardName: resolved.functionCall,
            inverseName: resolved.functionCall,
            carrierType: entry.typeName ?? "(none)"
        )
        return VerifyStubBundle(source: source, rendererContext: context)
    }
}
