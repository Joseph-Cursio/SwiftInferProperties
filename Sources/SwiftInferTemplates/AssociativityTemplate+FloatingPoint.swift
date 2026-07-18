import SwiftInferCore

// V1.4.3 floating-point counter-signal + advisory, extracted so the primary
// template stays under SwiftLint's file_length cap. Members are `static`
// (module-internal) rather than `private` so the cross-file callers in
// `AssociativityTemplate.accumulatedSignals` / `makeExplainability` resolve.
extension AssociativityTemplate {

    /// V1.4.3 — fires when the candidate's parameter type is a
    /// curated IEEE 754 floating-point-storage name (Float / Double /
    /// Float16-80 / CGFloat / Complex / Decimal). Drops Score 30 → 20
    /// (Possible-tier floor) so the suggestion stays surfaced under
    /// `--include-possible` for the explainability kit-pointer to be
    /// visible. Calibration cycle 1 tuning patch.
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
                + "associativity is not bit-exact under IEEE 754 sampling"
        )
    }

    /// V1.4.3 — produces a type-aware floating-point caveat when the
    /// candidate's parameter type is FP-storage, replacing the static
    /// "may fail sampling" warning with a more specific kit-pointer or
    /// cycle-2 deferral note. Returns `nil` when T isn't FP-storage —
    /// the caller falls back to the static M1-era warning.
    static func floatingPointAdvisory(for summary: FunctionSummary) -> String? {
        guard let first = summary.parameters.first,
              FloatingPointStorageNames.contains(first.typeText) else {
            return nil
        }
        let stripped = FloatingPointStorageNames.strippingGenericParameters(first.typeText)
        if FloatingPointStorageNames.isKitSupported(first.typeText) {
            return "T = \(stripped) conforms to FloatingPoint. Associativity holds "
                + "in principle; exact-equality auto-sampling fails on IEEE 754 rounding. "
                + "Verify via a finite-only generator (e.g. "
                + "`Gen<Double>.double(in: -1e6...1e6)`) per PropertyLawKit's "
                + "`FloatingPointLaws.swift` posture — kit "
                + "`checkFloatingPointPropertyLaws` covers FP-specific laws (NaN, "
                + "infinity), algebraic associativity needs the finite-only opt-in. "
                + "v1.5+ will surface the generator override automatically."
        }
        return "T = \(stripped) has IEEE 754 floating-point storage. Associativity "
            + "holds in principle; exact-equality auto-sampling fails on rounding. "
            + "Verify via a finite-only generator (e.g. "
            + "`Gen<Double>.double(in: -1e6...1e6)` lifted into \(stripped)) per "
            + "PropertyLawKit's `FloatingPointLaws.swift` tolerance posture. v1.5+ "
            + "will surface the generator override automatically."
    }
}
