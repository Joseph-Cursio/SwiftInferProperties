import SwiftInferCore
import SwiftInferTestLifter

/// M11.2 — equivalence-class union helpers consumed by
/// `LiftedSuggestionPipeline.promote(...)`. Split out of
/// `LiftedSuggestionPipeline.swift` to keep that file under
/// SwiftLint's 400-line cap.
///
/// Two helpers:
/// 1. `equivalenceClassLifted(from:summariesByName:)` — folds detector
///    survivors into the lifted-suggestion stream so they flow through
///    the standard recovery / promotion / suppression machinery.
/// 2. `equivalenceClassHintMap(from:summaries:)` — produces the
///    per-suggestion-identity hint map the `InteractiveTriage.Context`
///    carries to the accept-flow renderer (decoupled from
///    `Suggestion`'s storage shape so the hint doesn't inline-bloat
///    every TemplateEngine suggestion's optional storage and regress
///    the §13 row 4 memory ceiling).
extension LiftedSuggestionPipeline {

    /// Runs the M11.1 detector against each partition candidate (with
    /// `summariesByName` for the predicate-shape veto + `true` for
    /// `predicateArgGeneratable` per the M10.3 deferred-veto posture)
    /// and emits one `LiftedSuggestion.equivalenceClass(...)` per
    /// surviving partition. The lifted records use a synthetic
    /// `LiftedOrigin` keyed on the predicate name (the partition is a
    /// corpus-level finding; no single test method is canonical).
    static func equivalenceClassLifted(
        from candidates: [PartitionCandidate],
        summariesByName: [String: FunctionSummary]
    ) -> [LiftedSuggestion] {
        candidates.compactMap { candidate -> LiftedSuggestion? in
            let predicateSummary = summariesByName[candidate.predicateName]
            guard let hint = PredicateEquivalenceClassDetector.detect(
                candidate: candidate,
                predicateSummary: predicateSummary,
                predicateArgGeneratable: true
            ) else {
                return nil
            }
            let originLocation = predicateSummary?.location
                ?? SourceLocation(file: "<corpus>", line: 0, column: 0)
            let origin = LiftedOrigin(
                testMethodName: "equivalence-class:\(candidate.predicateName)",
                sourceLocation: originLocation
            )
            return LiftedSuggestion.equivalenceClass(hint: hint, origin: origin)
        }
    }

    /// Runs the M11.1 detector against the same candidate set
    /// `equivalenceClassLifted(from:summariesByName:)` consumes, but
    /// returns the per-suggestion-identity hint map the
    /// `InteractiveTriage.Context` carries to the accept-flow renderer.
    /// The identity input matches `LiftedSuggestion.equivalenceClass(...)`'s
    /// `makeIdentity()` shape — `"lifted|equivalence-class|<predicate>"` —
    /// so the lookup at accept-flow time hits exactly the post-promotion
    /// suggestion's `identity`.
    public static func equivalenceClassHintMap(
        from candidates: [PartitionCandidate],
        summaries: [FunctionSummary]
    ) -> [SuggestionIdentity: EquivalenceClassHint] {
        let summariesByName = LiftedSuggestionRecovery.summariesByName(summaries)
        var map: [SuggestionIdentity: EquivalenceClassHint] = [:]
        for candidate in candidates {
            let predicateSummary = summariesByName[candidate.predicateName]
            guard let hint = PredicateEquivalenceClassDetector.detect(
                candidate: candidate,
                predicateSummary: predicateSummary,
                predicateArgGeneratable: true
            ) else { continue }
            let identity = SuggestionIdentity(
                canonicalInput: "lifted|equivalence-class|\(hint.predicateName)"
            )
            map[identity] = hint
        }
        return map
    }
}
