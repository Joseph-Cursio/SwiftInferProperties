import Foundation
import SwiftInferCore

/// V2.0 M4.A — namespace housing the interaction-invariant template
/// engine. PRD §5's analog of v1's `TemplateEngine` / `TemplateRegistry`
/// for interaction-shaped (rather than algebraic) suggestions.
///
/// **M4.A scope (this commit):** namespace + the `analyze(candidates:)`
/// dispatch entry. The dispatch itself returns an empty list at M4.A
/// — no template ships at this sub-cycle. M4.B / M4.C add the first
/// two templates (Conservation / Idempotence, lifted from v1);
/// M5–M7 add Cardinality / Referential integrity / Biconditional.
///
/// **Why a namespace, not a registry value.** v1's
/// `TemplateRegistry` is a value type that holds an array of
/// `Template` instances. v2.0's template surface is smaller (5
/// families vs v1's 7+ templates) and each family is fundamentally a
/// pair of (witness detector, predicate emitter). A static-dispatch
/// namespace keeps the call site flat and avoids the indirection
/// without losing per-family extensibility — M4.B can add
/// `analyzeConservation(_:)` alongside `analyze(candidates:)` and
/// the namespace dispatch just calls each in turn.
public enum InteractionTemplateEngine {

    /// V2.0 M4.A — dispatch entry. Walks each reducer candidate,
    /// runs every shipped per-family analyzer (M4.B's Conservation
    /// is the first; M4.C / M5 / M6 / M7 layer in the rest),
    /// returns the accumulated suggestions sorted by descending
    /// score (matching v1's `TemplateRegistry.combine`).
    ///
    /// `sourcesDirectory` is the target's source root (e.g.
    /// `Sources/MyApp/`) — required at M4.B for Conservation's
    /// witness detector to walk the State struct's source. Family
    /// analyzers that don't need source access (Idempotence's
    /// Action-name pattern detector, etc.) ignore it.
    ///
    /// `firstSeenAt` defaults to the current wall-clock time — the
    /// caller can override for byte-stable test output. The returned
    /// suggestions get this timestamp as their §17.2 first-surfaced
    /// anchor.
    public static func analyze(
        candidates: [ReducerCandidate],
        sourcesDirectory: URL? = nil,
        firstSeenAt: Date = Date()
    ) throws -> [InteractionInvariantSuggestion] {
        var emitted: [InteractionInvariantSuggestion] = []
        for candidate in candidates {
            emitted.append(contentsOf: try analyzeOne(
                candidate,
                sourcesDirectory: sourcesDirectory,
                firstSeenAt: firstSeenAt
            ))
        }
        return emitted.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.identity.normalized < rhs.identity.normalized
        }
    }

    /// V2.0 M4.B/C — per-candidate dispatcher. Routes through every
    /// shipped per-family analyzer. Each analyzer is best-effort —
    /// if it can't produce a suggestion (witness absent, signature
    /// shape unsupported, etc.) it returns an empty slice.
    static func analyzeOne(
        _ candidate: ReducerCandidate,
        sourcesDirectory: URL?,
        firstSeenAt: Date
    ) throws -> [InteractionInvariantSuggestion] {
        var collected: [InteractionInvariantSuggestion] = []
        guard let sourcesDirectory else { return collected }
        // V2.0 M4.B — Conservation (count-shaped variant)
        let conservationWitnesses = try ConservationWitnessDetector.detect(
            stateTypeName: candidate.stateTypeName,
            in: sourcesDirectory
        )
        collected.append(contentsOf: ConservationInteractionTemplate.analyze(
            candidate: candidate,
            witnesses: conservationWitnesses,
            firstSeenAt: firstSeenAt
        ))
        // V2.0 M4.C — Idempotence (action-case-name pattern)
        let idempotenceWitnesses = try IdempotenceWitnessDetector.detect(
            actionTypeName: candidate.actionTypeName,
            in: sourcesDirectory
        )
        collected.append(contentsOf: IdempotenceInteractionTemplate.analyze(
            candidate: candidate,
            witnesses: idempotenceWitnesses,
            firstSeenAt: firstSeenAt
        ))
        // V2.0 M5 — Cardinality (≥ 2 presentation-flag fields)
        let cardinalityWitnesses = try CardinalityWitnessDetector.detect(
            stateTypeName: candidate.stateTypeName,
            in: sourcesDirectory
        )
        collected.append(contentsOf: CardinalityInteractionTemplate.analyze(
            candidate: candidate,
            witnesses: cardinalityWitnesses,
            firstSeenAt: firstSeenAt
        ))
        // V2.0 M6 — Referential Integrity (selectedX + xs pair)
        let refIntegrityWitnesses = try ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: candidate.stateTypeName,
            in: sourcesDirectory
        )
        collected.append(contentsOf: ReferentialIntegrityInteractionTemplate.analyze(
            candidate: candidate,
            witnesses: refIntegrityWitnesses,
            firstSeenAt: firstSeenAt
        ))
        // V2.0 M7 — Biconditional / iff (Bool flag + Optional pair)
        let biconditionalWitnesses = try BiconditionalWitnessDetector.detect(
            stateTypeName: candidate.stateTypeName,
            in: sourcesDirectory
        )
        collected.append(contentsOf: BiconditionalInteractionTemplate.analyze(
            candidate: candidate,
            witnesses: biconditionalWitnesses,
            firstSeenAt: firstSeenAt
        ))
        return collected
    }
}
