import SwiftInferCore

// V1.43 cleanup — signals/vetoes/builders live here so the primary
// enum body stays under SwiftLint's type_body_length cap.
extension IdempotenceTemplate {

    // MARK: - Signals

    static func nameSignal(
        for summary: FunctionSummary,
        vocabulary: Vocabulary
    ) -> Signal? {
        // Curated takes precedence over project vocabulary so a verb
        // already in the curated list never double-fires when the project
        // happens to repeat it. Both contribute the same +40 weight per
        // PRD §4.5; only the rendered detail line distinguishes them.
        if curatedVerbs.contains(summary.name) {
            return Signal(
                kind: .exactNameMatch,
                weight: 40,
                detail: "Curated idempotence verb match: '\(summary.name)'"
            )
        }
        if vocabulary.idempotenceVerbs.contains(summary.name) {
            return Signal(
                kind: .exactNameMatch,
                weight: 40,
                detail: "Project-vocabulary idempotence verb match: '\(summary.name)'"
            )
        }
        return nil
    }

    static func selfCompositionSignal(for summary: FunctionSummary) -> Signal? {
        guard summary.bodySignals.hasSelfComposition else {
            return nil
        }
        return Signal(
            kind: .selfComposition,
            weight: 20,
            detail: "Self-composition detected in body: \(summary.name)(\(summary.name)(x))"
        )
    }

    /// V1.10.1 — fires when the candidate's first-parameter argument label
    /// is in `DirectionLabels.curated` (e.g., `index(after:)`,
    /// `bucket(before:)`). Emits weight `-15` so type-symmetry's `+30`
    /// collapses to `+15` → Suppressed tier (< 20). Curated-verb matches
    /// add `+40` and override (net `+55` → Likely tier preserved). Closes
    /// the cycle-6 0/10 idempotence rejection pattern's dominant 5-of-10
    /// sub-pattern.
    ///
    /// **V1.13.1.** Hoisted out of `IdempotenceTemplate.directionLabels`
    /// to `SwiftInferCore.DirectionLabels.curated` once round-trip became
    /// the third consumer in cycle 9. See `DirectionLabels` for the
    /// historical motivation.
    static func directionLabelCounterSignal(
        for summary: FunctionSummary
    ) -> Signal? {
        guard let label = summary.parameters.first?.label,
              DirectionLabels.curated.contains(label) else {
            return nil
        }
        // V1.25.A — name-prefix gated magnitude bump. When the function
        // name starts with an index-advance prefix (`index*`, `bucket*`,
        // `word*`), the joint match (direction-label + index-advance
        // name) is high-confidence non-idempotent — bump -15 → -25 (full
        // veto-equivalent). Closes the cycle-21 finding: 13+ OC
        // `index(after:)`/`index(before:)` direction-op idempotence
        // rejects dominate the residual idempotence non-lifted pool.
        // Cycle-21 finding doc: identified post-v1.24 as the next
        // priority.
        let name = summary.name
        let isIndexAdvanceName = name.hasPrefix("index")
            || name.hasPrefix("bucket")
            || name.hasPrefix("word")
        if isIndexAdvanceName {
            return Signal(
                kind: .directionLabel,
                weight: -25,
                detail: "Index-advance direction-label: '\(name)(\(label):)' — "
                    + "name-prefix + direction-label joint match identifies "
                    + "positional cursor advance, not a fixed-point operation; "
                    + "lifted shadow not idempotent"
            )
        }
        return Signal(
            kind: .directionLabel,
            weight: -15,
            detail: "Direction-label argument: '\(label)' — function is likely "
                + "directional (increment/decrement) rather than idempotent"
        )
    }

    /// V1.5.2 — fires when the candidate type already conforms to a
    /// protocol whose published laws cover the idempotence property
    /// the template would emit. Candidate properties span
    /// `setIntersectionIdempotent` (covered by SetAlgebra) +
    /// `semilatticeIdempotence` (covered by kit Semilattice). Generic
    /// `f(f(x))` on arbitrary types isn't covered — the veto fires
    /// only when the type's conformance set intersects the curated
    /// idempotence-bearing protocols.
    static func assumedKitCoverage(
        for summary: FunctionSummary,
        inheritedTypesByName: [String: Set<String>]
    ) -> Signal? {
        ProtocolCoverageMap.assumedCoverageSignal(
            forTypeText: summary.parameters.first?.typeText,
            inheritedTypesByName: inheritedTypesByName,
            candidateProperties: [.setIntersectionIdempotent, .semilatticeIdempotence]
        )
    }
}
