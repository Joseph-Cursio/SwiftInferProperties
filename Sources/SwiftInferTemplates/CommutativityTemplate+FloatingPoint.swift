import SwiftInferCore

// V1.4.3 floating-point counter-signal + advisory, extracted so the primary
// template stays under SwiftLint's file_length cap. Members are `static`
// (module-internal) rather than `private` so the cross-file callers in
// `CommutativityTemplate.accumulatedSignals` / `makeExplainability` resolve.
extension CommutativityTemplate {

    /// V1.4.3 — fires when the candidate's parameter type is a
    /// curated IEEE 754 floating-point-storage name. Drops Score 30 →
    /// 20 (Possible-tier floor) so the explainability kit-pointer
    /// stays visible under `--include-possible`. Mirrors
    /// AssociativityTemplate.floatingPointStorageCounterSignal.
    static func floatingPointStorageCounterSignal(
        for summary: FunctionSummary
    ) -> Signal? {
        guard let first = summary.parameters.first,
              FloatingPointStorageNames.contains(first.typeText) else {
            return nil
        }
        let stripped = FloatingPointStorageNames.strippingGenericParameters(first.typeText)
        return Signal(
            kind: .floatingPointStorage,
            weight: -10,
            detail: "Floating-point storage: T = \(stripped) — exact-equality "
                + "commutativity is not bit-exact under IEEE 754 sampling on edge values"
        )
    }

    /// V1.4.3 — type-aware FP advisory paralleling
    /// AssociativityTemplate.floatingPointAdvisory. `nil` when T isn't
    /// FP-storage; caller skips the FP caveat in that case.
    static func floatingPointAdvisory(for summary: FunctionSummary) -> String? {
        guard let first = summary.parameters.first,
              FloatingPointStorageNames.contains(first.typeText) else {
            return nil
        }
        let stripped = FloatingPointStorageNames.strippingGenericParameters(first.typeText)
        if FloatingPointStorageNames.isKitSupported(first.typeText) {
            return "T = \(stripped) conforms to FloatingPoint. Commutativity holds "
                + "in principle; exact-equality auto-sampling fails on IEEE 754 NaN "
                + "edge cases (`NaN == NaN` is false). Verify via a finite-only "
                + "generator (e.g. `Gen<Double>.double(in: -1e6...1e6)`) per "
                + "PropertyLawKit's `FloatingPointLaws.swift` posture — kit "
                + "`checkFloatingPointPropertyLaws` covers NaN-domain laws "
                + "separately, algebraic commutativity needs the finite-only "
                + "opt-in. v1.5+ will surface the generator override automatically."
        }
        return "T = \(stripped) has IEEE 754 floating-point storage. Commutativity "
            + "holds in principle; exact-equality auto-sampling fails on NaN edge "
            + "cases. Verify via a finite-only generator (e.g. "
            + "`Gen<Double>.double(in: -1e6...1e6)` lifted into \(stripped)) per "
            + "PropertyLawKit's `FloatingPointLaws.swift` tolerance posture. v1.5+ "
            + "will surface the generator override automatically."
    }
}
