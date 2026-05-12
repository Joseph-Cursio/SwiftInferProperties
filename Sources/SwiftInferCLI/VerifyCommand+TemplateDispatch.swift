import Foundation
import SwiftInferCore

/// V1.44.D — template dispatch lives here so `VerifyCommand.swift`
/// stays under the file-length cap. Extends `SwiftInferCommand.Verify`
/// with the per-template stub-bundle builders.
///
/// Bundle of the synthesized stub source + the renderer context it
/// implies. File-scoped (not nested in `Verify`) to keep the type-
/// hierarchy within SwiftLint's `nesting` rule.
struct VerifyStubBundle {
    let source: String
    let rendererContext: VerifyResultRenderer.Context
}

extension SwiftInferCommand.Verify {

    /// Dispatch on `entry.templateName` to the per-template builder.
    /// Unsupported templates (`commutativity`, `dual-style-consistency`,
    /// etc.) raise `.unsupportedTemplate`; v1.45+ will widen the
    /// supported set.
    static func buildStubBundle(
        entry: SemanticIndexEntry,
        budget: RoundTripStubEmitter.TrialBudget
    ) throws -> VerifyStubBundle {
        switch entry.templateName {
        case "round-trip":
            return try roundTripStubBundle(entry: entry, budget: budget)
        case "idempotence":
            return try idempotenceStubBundle(entry: entry, budget: budget)
        default:
            throw VerifyError.unsupportedTemplate(
                template: entry.templateName,
                expected: ["round-trip", "idempotence"]
            )
        }
    }

    private static func roundTripStubBundle(
        entry: SemanticIndexEntry,
        budget: RoundTripStubEmitter.TrialBudget
    ) throws -> VerifyStubBundle {
        let pair = try RoundTripPairResolver.resolve(entry)
        let source = try RoundTripStubEmitter.emit(
            RoundTripStubEmitter.Inputs(
                forwardCall: pair.forwardCall,
                inverseCall: pair.inverseCall,
                extraImports: [],
                carrierType: entry.typeName ?? "(none)",
                seedHex: makeSeedHex(from: entry.identityHash),
                trialBudget: budget
            )
        )
        let context = VerifyResultRenderer.Context(
            templateName: "round-trip",
            forwardName: pair.forwardCall,
            inverseName: pair.inverseCall,
            carrierType: entry.typeName ?? "(none)"
        )
        return VerifyStubBundle(source: source, rendererContext: context)
    }

    private static func idempotenceStubBundle(
        entry: SemanticIndexEntry,
        budget: IdempotenceStubEmitter.TrialBudget
    ) throws -> VerifyStubBundle {
        let resolved = try IdempotencePairResolver.resolve(entry)
        let source = try IdempotenceStubEmitter.emit(
            IdempotenceStubEmitter.Inputs(
                functionCall: resolved.functionCall,
                extraImports: [],
                carrierType: entry.typeName ?? "(none)",
                seedHex: makeSeedHex(from: entry.identityHash),
                trialBudget: budget
            )
        )
        let context = VerifyResultRenderer.Context(
            templateName: "idempotence",
            forwardName: resolved.functionCall,
            inverseName: resolved.functionCall,
            carrierType: entry.typeName ?? "(none)"
        )
        return VerifyStubBundle(source: source, rendererContext: context)
    }
}
