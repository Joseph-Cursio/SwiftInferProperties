import SwiftInferCore

// Call resolution for `documented-range` (#701), in its own file because
// `+CallResolution` holds the shared switch at its body cap and this law's two
// refusals need their rationale beside them.
extension SwiftInferCommand.Verify {

    /// The datum a `documented-range` entry indexed before #701 lacks, phrased for
    /// `VerifyError.staleIndexEntry`. Shared with `composeDocumentedRangePass`, which guards the
    /// same absence on a hand-built `Inputs`, so both refusals read alike.
    static let documentedRangeMissingReason =
        "it records no bounds for the range its doc comment states "
            + "(`documentedRange`, added 2026-11-13)"

    /// The call for the laws built on totality's operands: `predicate`'s receiver-shaped single
    /// call as it always was, and `documented-range`'s, which is the same call behind two
    /// refusals. One entry point so the two share a `resolveFunctionCalls` arm.
    static func resolveTotalityShapedCalls(
        entry: SemanticIndexEntry,
        typeQualifier: String,
        funcName: String
    ) throws -> ResolvedCalls {
        guard entry.templateName == TemplateName.documentedRange.rawValue else {
            return singleCallResolved(
                entry: entry,
                typeQualifier: typeQualifier,
                funcName: funcName,
                receiverShape: entry.isInstanceMethod
            )
        }
        return try resolveDocumentedRangeCalls(entry: entry, typeQualifier: typeQualifier, funcName: funcName)
    }

    /// Resolve the one call of `(L...U as ClosedRange<Double>).contains(Double(f(x)))`.
    ///
    /// The call is `predicate`'s: the receiver closure (`{ $0.progress }`,
    /// `{ $0.ratio(of: $1) }`) for an instance member, the static or free label trampoline
    /// otherwise, applied by the composer to one generated value per parameter. The renderer's
    /// INVERSE name carries the range literal (`0.0...1.0`) instead of a second call: this law
    /// names no second function, and `RenderShape.documentedRange` prints the bounds the
    /// verdict is about from it, since `VerifyResultRenderer.Context` has no slot for them.
    ///
    /// Two refusals, both before anything is emitted:
    /// - **no bounds** → `staleIndexEntry`. The bounds were parsed at discover time and dropped
    ///   by the index until #701, and the doc comment they came from is not indexed, so there is
    ///   nothing to re-derive them from. Re-indexing writes them.
    /// - **no input** → `noInputToGenerate`. A static member with no parameters is admitted by
    ///   the template (`DocumentedRangeTemplate.statedRange` takes a containing type in place of
    ///   parameters) but has nothing to draw: the single-carrier fallback would pass a generated
    ///   value to a call that takes none, which does not compile. `accept` declines the same
    ///   shape (`applicationArity > 0` in `InteractiveTriage+AcceptTotality.swift`).
    static func resolveDocumentedRangeCalls(
        entry: SemanticIndexEntry,
        typeQualifier: String,
        funcName: String
    ) throws -> ResolvedCalls {
        let template = TemplateName.documentedRange.rawValue
        guard let range = entry.documentedRange else {
            throw VerifyError.staleIndexEntry(
                template: template,
                primary: entry.primaryFunctionName,
                reason: documentedRangeMissingReason
            )
        }
        guard entry.isInstanceMethod || !argumentLabels(from: entry.primaryFunctionName).isEmpty else {
            throw VerifyError.noInputToGenerate(template: template, primary: entry.primaryFunctionName)
        }
        let call = singleCallResolved(
            entry: entry,
            typeQualifier: typeQualifier,
            funcName: funcName,
            receiverShape: entry.isInstanceMethod
        )
        return ResolvedCalls(
            expressions: call.expressions,
            rendererForwardName: call.rendererForwardName,
            rendererInverseName: "\(range.lower)...\(range.upper)"
        )
    }
}
