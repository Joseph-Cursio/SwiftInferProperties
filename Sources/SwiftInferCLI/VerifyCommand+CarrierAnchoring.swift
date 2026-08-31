import Foundation
import SwiftInferCore

/// **What type does a template's generator quantify over?**
///
/// `roundTripDomainCarrier` (in `VerifyCommand+TemplateDispatch.swift`) answers it for
/// `round-trip`; this answers it for `monotonicity`. They were separated only by accident of
/// history, and the accident cost something: **the monotonicity rule was missing for as long as
/// it was because the round-trip one states it in a docstring nobody had reason to read** —
///
/// > *instance-method forward — the value IS the receiver, so the declaring type is already
/// > right*
///
/// Split out on 2026-08-30 when this rule's reasoning pushed that file past its 400-line cap.
/// The seam is clean and the reasoning is what a later reader needs; shaving the comment would
/// have removed exactly that.
extension SwiftInferCommand.Verify {

    /// **Instance-method `monotonicity` anchors at the RECEIVER, not the parameter.**
    ///
    /// `roundTripDomainCarrier` above already states this rule and guards `round-trip` with it:
    /// *"instance-method forward — the value IS the receiver, so the declaring type is already
    /// right."* It was never applied to `monotonicity`, so `OrderedSet.index(before:)` derived a
    /// `Generator<Int>` — the parameter — and emitted `OrderedSet.index(before: someInt)`, a
    /// **static call on an instance method**. Measured on `swift-collections` @ `899809d3`:
    /// **31 of 64 `monotonicity` rows failed to build this way**, and they are the template's
    /// only genuinely order-related population.
    /// `docs/measurements/instance-method-shape-census.md`.
    ///
    /// ⚠ **GATED ON A CURATED RECIPE EXISTING, which is narrower than the rule deserves and is
    /// deliberate.** The unguarded rule — *any instance method anchors at its receiver* — is
    /// correct in principle and would change **19 further rows** (`Deque`, `BitArray`,
    /// `UniqueDeque`, `RigidDeque`, `UniqueArray`, …) from one failure mode to another **that has
    /// not been measured**. This project has already paid once this week for shipping half of a
    /// two-part fix on reasoning alone: the earlier carrier-spelling normalisation was correct,
    /// inert without this clause, and measured at **zero rows moved**. So this admits exactly the
    /// carriers the curated table can serve, and widening it is a separate, measured step.
    static func monotonicityReceiverCarrier(entry: SemanticIndexEntry) -> String? {
        guard entry.templateName == "monotonicity",
              entry.isInstanceMethod,
              let owner = entry.typeName,
              !owner.isEmpty,
              StrategistDispatchEmitter.curatedOCRecipe(carrier: owner) != nil
        else { return nil }
        return owner
    }
}
