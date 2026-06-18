import SwiftInferCore

/// V1.24.B — explicit non-idempotent mutator-name veto on
/// `IdempotenceTemplate.suggest(forLifted:)`. Direct cycle-20 finding
/// closure (V1.20.C 4/4 reject on OC `reverse()`, `removeFirst()`,
/// `removeLast()`, `OrderedSet.reverse()` lifted-idempotence picks).
///
/// Fires `Signal.vetoWeight` when `lifted.originalSummary.name ∈
/// MutatorBlockedFromIdempotence.curated`. The veto fires on **any
/// value-semantic carrier** (no protocol-conformance requirement) —
/// distinct from V1.21.A's `iteratorProtocolCarrierVeto` which requires
/// IteratorProtocol conformance + curated Iterator-method-name.
///
/// **Why no carrier-protocol gate:** the names `reverse` / `removeFirst`
/// / `removeLast` / etc. are canonical Swift mutating-method names
/// whose semantic content is non-idempotent by structural construction,
/// regardless of the carrier's protocol stack. `OrderedDictionary.reverse()`
/// (RangeReplaceableCollection-conforming, NOT IteratorProtocol) is
/// non-idempotent for the same reason `Array.reverse()` is. The cycle-20
/// sample confirmed this: 4/4 reject on OC carriers that don't conform
/// to IteratorProtocol.
///
/// Mechanism class: extension of class 7 (function-name + type-shape
/// composite, V1.14.1 / V1.16.1 / V1.21.A / V1.21.C lineage). Generalizes
/// V1.21.A's pattern from Iterator-conforming carriers to any value-
/// semantic carrier.
extension IdempotenceTemplate {

    /// Returns a veto `Signal` (weight `Signal.vetoWeight`) when the
    /// lifted suggestion's underlying mutating-method name is in
    /// `MutatorBlockedFromIdempotence.curated`. `nil` otherwise.
    ///
    /// Wired into `IdempotenceTemplate.suggest(forLifted:)` via
    /// `liftedAuxiliarySignals(...)` alongside V1.21.A
    /// `iteratorProtocolCarrierVeto`.
    static func mutatorBlocklistVeto(
        forLifted lifted: LiftedTransformation
    ) -> Signal? {
        let methodName = lifted.originalSummary.name
        guard MutatorBlockedFromIdempotence.curated.contains(methodName) else {
            return nil
        }
        return Signal(
            kind: .protocolCoveredProperty,
            weight: Signal.vetoWeight,
            detail: "Mutator '\(methodName)' is canonical-Swift non-idempotent "
                + "by structural construction — `\(methodName)()` advances state "
                + "(removeFirst/removeLast/popFirst/popLast/dropFirst/dropLast), "
                + "inverts ordering (reverse), or is a self-inverse involution "
                + "(negate/toggle/invert/complement/twosComplement); lifted shadow "
                + "is not idempotent regardless of carrier protocol conformance"
        )
    }
}
