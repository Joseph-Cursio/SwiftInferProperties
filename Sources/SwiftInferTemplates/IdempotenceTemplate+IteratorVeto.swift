import SwiftInferCore

/// V1.21.A — direct cycle-17 finding closure. Suppresses
/// `IdempotenceTemplate.suggest(forLifted:)` candidates whose carrier
/// conforms to `IteratorProtocol` (or whose name + method signature
/// match the canonical Iterator-pattern shape). The cycle-17 triage
/// measured 4/4 reject on Iterator-shape lifted-idempotence picks
/// (`AdjacentPairsSequence.Iterator.next()`, `Combinations.Iterator.next()`,
/// `ChunkedIterator.advance()`, `_HashTable.BucketIterator.advance()`):
/// `IteratorProtocol.next()` advances state per call by protocol
/// contract, so the lifted shadow `(Iterator) -> Iterator` is NOT
/// idempotent regardless of carrier value-semantics.
///
/// Mechanism class: extension of class 7 (function-name + type-shape
/// composite, V1.14.1 / V1.16.1 lineage) — the gate is on the
/// **carrier's protocol conformance** rather than the function's name +
/// type-shape. Same scoring posture as V1.14.1: full veto via
/// `Signal.vetoWeight` collapses the score to Suppressed (filtered from
/// `--include-possible` output). Calibration record preserved per V1.5.2
/// rationale — the suggestion still scores; it just lands in Suppressed
/// and gets filtered.
///
/// Two detection paths:
///
/// 1. **Primary — textual conformance** via the V1.5.2-built
///    `inheritedTypesByName` index. When the corpus declares
///    `extension <Carrier>: IteratorProtocol` (or `struct Iterator:
///    IteratorProtocol`), the index records `Carrier → {..., IteratorProtocol}`.
///    The veto fires on intersection with `"IteratorProtocol"`.
///
/// 2. **Name fallback** — when the corpus's `inheritedTypesByName` lookup
///    misses (e.g., the carrier's TypeDecl wasn't captured because the
///    extension lives in a non-scanned compilation unit), but the carrier
///    name + method name jointly match the Iterator pattern. Conservative:
///    requires BOTH `carrier == "Iterator" || carrier.hasSuffix(".Iterator")`
///    AND `methodName ∈ iteratorMethodNames`. This combination is unlikely
///    to match a value-semantic-but-truly-idempotent type.
///
/// Per the v1.21 plan §"Open decisions" #1 lean: textual-conformance +
/// name-fallback (option b). Cycle-19 measurement on broader corpora
/// will quantify the false-positive risk on the name-fallback path.
extension IdempotenceTemplate {

    /// Curated set of method names canonical to the Iterator pattern.
    /// Used by the name-fallback path only — the primary
    /// `IteratorProtocol` conformance match doesn't consult this set
    /// (any `mutating func` on an Iterator-conforming carrier is
    /// state-advancing by protocol contract).
    ///
    /// **V1.22.A extension** — adds `findNext` + `advanceToNextUnoccupiedBucket`
    /// per the cycle-18 finding (3 surviving OC `_HashTable.BucketIterator`
    /// picks at v1.21 used these non-curated method names). Both are
    /// stateful-incremental by Iterator-pattern convention.
    static let iteratorMethodNames: Set<String> = [
        "next",
        "advance",
        "nextState",
        "step",
        "findNext",
        "advanceToNextUnoccupiedBucket"
    ]

    /// Returns a veto `Signal` (weight `Signal.vetoWeight`) when the
    /// lifted suggestion's carrier is Iterator-shaped. Returns `nil`
    /// when neither the conformance match nor the name-fallback
    /// condition holds.
    ///
    /// Wired into `IdempotenceTemplate.suggest(forLifted:)` via
    /// `liftedAuxiliarySignals(...)`.
    static func iteratorProtocolCarrierVeto(
        for lifted: LiftedTransformation,
        inheritedTypesByName: [String: Set<String>]
    ) -> Signal? {
        let carrier = lifted.carrier
        let methodName = lifted.originalSummary.name

        // Primary path: textual conformance to `IteratorProtocol` via the
        // V1.5.2 corpus index. Strip generic parameters before lookup
        // (matches `ProtocolCoverageMap.coverageVetoSignal` posture).
        let strippedCarrier = ProtocolCoverageMap.strippingGenericParameters(carrier)
        if let inherited = inheritedTypesByName[strippedCarrier],
           inherited.contains("IteratorProtocol") {
            return Signal(
                kind: .protocolCoveredProperty,
                weight: Signal.vetoWeight,
                detail: "Carrier '\(carrier)' conforms to IteratorProtocol — "
                    + "`\(methodName)()` advances state per call by protocol "
                    + "semantics; lifted shadow `(Iterator) -> Iterator` is not "
                    + "idempotent regardless of value-semantics admission"
            )
        }

        // V1.27.A — Sequence-conformance fallback. Cycle-23 finding closure:
        // 2 Algo idempotence-lifted picks reject (cycle-23 #14, #15) on
        // Sequence-conforming carriers that expose `next()`/`advance()`
        // directly without explicit IteratorProtocol conformance. By
        // Sequence's contract, types defining `mutating func next()` on
        // themselves follow the same stateful-iterator pattern as
        // IteratorProtocol conformers — the lifted shadow advances state
        // and is not idempotent.
        if let inherited = inheritedTypesByName[strippedCarrier],
           inherited.contains("Sequence"),
           iteratorMethodNames.contains(methodName) {
            return Signal(
                kind: .protocolCoveredProperty,
                weight: Signal.vetoWeight,
                detail: "Carrier '\(carrier)' conforms to Sequence + method "
                    + "'\(methodName)' is a canonical Iterator-pattern advance — "
                    + "Sequence's contract implies stateful iteration; lifted "
                    + "shadow not idempotent"
            )
        }

        // Name fallback: carrier-name + method-name joint match. Catches
        // Iterator-shape types whose conformance the corpus index didn't
        // capture (e.g., conformance declared in a non-scanned source file
        // or implicit via a foreign extension).
        //
        // **V1.22.A extension** — match `*Iterator` suffix (without the dot)
        // so `BucketIterator`, `HashIterator`, `MyArrayIterator` etc. are
        // caught alongside `Iterator` and `Foo.Iterator`. The joint match
        // (curated method name AND Iterator-shape carrier) preserves the
        // false-positive guardrail from V1.21.A.
        let isIteratorNamed = carrier == "Iterator"
            || carrier.hasSuffix(".Iterator")
            || carrier.hasSuffix("Iterator")
        if isIteratorNamed, iteratorMethodNames.contains(methodName) {
            return Signal(
                kind: .protocolCoveredProperty,
                weight: Signal.vetoWeight,
                detail: "Carrier '\(carrier)' has Iterator-shape name and method "
                    + "'\(methodName)' is a canonical Iterator-pattern advance — "
                    + "lifted shadow is not idempotent (state advances per call)"
            )
        }

        return nil
    }
}
