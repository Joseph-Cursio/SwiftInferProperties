import SwiftInferCore

/// V1.24.C — non-deterministic mutator-name veto on
/// `IdempotenceTemplate.suggest(forLifted:)`. Direct cycle-20 finding
/// closure (V1.20.C #40 unknown verdict on `OrderedDictionary.shuffle()`).
///
/// Fires `Signal.vetoWeight` when `lifted.originalSummary.name ∈
/// NonDeterministicMutatorNames.curated`. Name-fallback approach per
/// the v1.24 plan §"Open decisions" #2 lean (extended body-signal RNG
/// detection deferred to v1.25+).
///
/// **Complements existing `nonDeterministicVeto`.** The existing
/// `IdempotenceTemplate.nonDeterministicVeto(for:)` (V1.4.x) fires
/// based on `bodySignals.hasNonDeterministicCall` — a body-walker
/// detector for known-RNG API calls. The cycle-20 measurement found
/// that detector misses some RNG patterns (OC `shuffle()` surfaced
/// despite using RNG). The V1.24.C name-fallback closes the gap for
/// the canonical Swift `shuffle` naming.
///
/// Mechanism class: extension of class 7 (function-name + type-shape
/// composite, V1.14.1 / V1.16.1 / V1.21.A / V1.21.C / V1.24.B lineage).
extension IdempotenceTemplate {

    /// Returns a veto `Signal` (weight `Signal.vetoWeight`) when the
    /// lifted suggestion's underlying mutating-method name is in
    /// `NonDeterministicMutatorNames.curated`. `nil` otherwise.
    ///
    /// Wired into `IdempotenceTemplate.suggest(forLifted:)` via
    /// `liftedAuxiliarySignals(...)` alongside V1.21.A
    /// `iteratorProtocolCarrierVeto` and V1.24.B `mutatorBlocklistVeto`.
    static func nonDeterministicMutatorVeto(
        forLifted lifted: LiftedTransformation
    ) -> Signal? {
        let methodName = lifted.originalSummary.name
        guard NonDeterministicMutatorNames.curated.contains(methodName) else {
            return nil
        }
        return Signal(
            kind: .nonDeterministicBody,
            weight: Signal.vetoWeight,
            detail: "Canonical non-deterministic mutator '\(methodName)' — "
                + "body is RNG-driven by Swift naming convention; lifted "
                + "shadow is not idempotent (and not any algebraic property) "
                + "regardless of carrier identity"
        )
    }
}
