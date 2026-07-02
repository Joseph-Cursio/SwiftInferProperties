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

    /// Helper — produce a copy of `entry` with `typeName` set to
    /// `carrier`. Used to thread the `GenericBindingResolver`-bound
    /// carrier into the per-template builders without leaking the
    /// bound form back to the SemanticIndex. (V1.149 — relocated here
    /// from `+TemplateDispatch` for the file-length cap; `carrierTypeName`
    /// is preserved so the generator carrier survives owner rebinding.)
    static func rebound(
        _ entry: SemanticIndexEntry,
        toCarrier carrier: String
    ) -> SemanticIndexEntry {
        guard entry.typeName != carrier else { return entry }
        return SemanticIndexEntry(
            identityHash: entry.identityHash,
            templateName: entry.templateName,
            typeName: carrier,
            score: entry.score,
            tier: entry.tier,
            primaryFunctionName: entry.primaryFunctionName,
            location: entry.location,
            decision: entry.decision,
            decisionAt: entry.decisionAt,
            firstSeenAt: entry.firstSeenAt,
            lastSeenAt: entry.lastSeenAt,
            typeShape: entry.typeShape,
            carrierTypeName: entry.carrierTypeName,
            isInstanceMethod: entry.isInstanceMethod,
            isMutatingMethod: entry.isMutatingMethod,
            isNullary: entry.isNullary,
            returnsSelfType: entry.returnsSelfType
        )
    }

    /// V1.149 — the argument labels of `primaryFunctionName` (e.g.
    /// `"indent(in:)"` → `["in"]`, `"pick(a:b:)"` → `["a", "b"]`,
    /// `"clamp(_:)"` → `["_"]`, `"f()"` → `[]`). Unlabeled parameters
    /// surface as `"_"`.
    static func argumentLabels(from primaryFunctionName: String) -> [String] {
        guard let open = primaryFunctionName.firstIndex(of: "("),
            let close = primaryFunctionName.lastIndex(of: ")"),
            open < close else { return [] }
        let inner = primaryFunctionName[primaryFunctionName.index(after: open)..<close]
        guard !inner.isEmpty else { return [] }
        return inner.split(separator: ":", omittingEmptySubsequences: true).map(String.init)
    }

    /// V1.149 — the call expression the stub applies positionally. A function
    /// with external argument labels can't be called `reference(value)`, so it
    /// gets a label-carrying trampoline closure (`{ reference(in: $0) }`) that
    /// the stub's `\(call)(args)` applies immediately. A label-free function
    /// (all labels `"_"`, or none) returns `reference` unchanged so existing
    /// stdlib-carrier stubs stay byte-identical.
    static func labeledCallExpression(
        primaryFunctionName: String,
        reference: String
    ) -> String {
        let labels = argumentLabels(from: primaryFunctionName)
        guard labels.contains(where: { $0 != "_" }) else { return reference }
        let placeholders = labels.enumerated().map { index, label in
            label == "_" ? "$\(index)" : "\(label): $\(index)"
        }
        let args = placeholders.joined(separator: ", ")
        return "{ \(reference)(\(args)) }"
    }
}
