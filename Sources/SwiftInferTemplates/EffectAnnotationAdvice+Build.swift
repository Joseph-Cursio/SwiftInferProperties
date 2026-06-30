import SwiftInferCore

extension EffectAnnotationAdvice {

    /// Build advice for a function the corpus scan flagged `isInferredPure`.
    /// Reuses the same `inferenceDisplayName` / `inferenceSignature` rendering
    /// the property-test templates use for their evidence rows, so the advice
    /// section reads consistently with the rest of `discover`.
    init(forPureFunction summary: FunctionSummary) {
        self.init(
            displayName: summary.inferenceDisplayName,
            signature: summary.inferenceSignature,
            location: summary.location
        )
    }

    /// The advisory records for every pure function in `summaries`, in source
    /// order (`summaries` is already source-ordered by the scan).
    public static func adviceList(from summaries: [FunctionSummary]) -> [EffectAnnotationAdvice] {
        summaries.filter(\.isInferredPure).map(Self.init(forPureFunction:))
    }
}
