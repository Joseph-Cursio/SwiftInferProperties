import SwiftInferCore

/// TestLifter M11.1 — pure-function detector that decides whether a
/// `PartitionCandidate` from `EquivalenceClassMarkerExtractor` qualifies
/// as a predicate equivalence class, and (when so) returns the
/// `EquivalenceClassHint` the M11.2 accept-flow renderer surfaces.
///
/// Inputs:
/// - `candidate`: the aggregated `(predicateName, markerPair)` partition
///   from M11.1's marker extractor — both buckets pre-validated for
///   homogeneous predicate name + matched-polarity assertions.
/// - `predicateSummary`: the `FunctionSummary` for the predicate function
///   from production-side scan output — drives the four predicate-shape
///   veto checks (throws / async / multi-arg / non-generatable arg type).
///   `nil` when the predicate isn't found in production code (treated as
///   `.predicateArgNotGeneratable`).
/// - `predicateArgGeneratable`: whether the predicate's single argument
///   type is auto-generatable per the M3+ `DerivationStrategist` strategy
///   table. Decoupled into a parameter so M11.1 unit tests don't need to
///   invoke the full strategist; the M11.2 pipeline computes this via
///   the existing `DerivationStrategist` lookup. Only consulted when
///   `predicateSummary` is non-nil with a single parameter.
///
/// Returns an `EquivalenceClassHint` when:
/// 1. `candidate.outlierSiteCount == 0` (one outlier kills, per PRD §3.5
///    conservative bias).
/// 2. `candidate.positiveSites.count >= 3` AND
///    `candidate.negativeSites.count >= 3` (per-bucket threshold mirrors
///    M4.3 / M9 / M10).
///
/// The hint's `predicateVeto` field is populated when one of the four
/// hard-veto checks fires, in priority order: throws > async > multi-arg
/// > non-generatable. The `suggestedPositiveGenerator` and
/// `suggestedNegativeGenerator` strings are always populated (rendered
/// as advisory text in the documentation block even when vetoed).
///
/// Returns `nil` otherwise.
public enum PredicateEquivalenceClassDetector {

    public static func detect(
        candidate: PartitionCandidate,
        predicateSummary: FunctionSummary?,
        predicateArgGeneratable: Bool
    ) -> EquivalenceClassHint? {
        // M13.1 — `PartitionCandidate.markerPair` widened to optional so
        // M13.2's N-class candidates can share the carrier shape. The
        // M11.1 two-class detector only fires on candidates that carry a
        // `markerPair`; N-class candidates flow through the M13.2
        // `NClassEquivalenceClassDetector` instead.
        guard let markerPair = candidate.markerPair else { return nil }
        guard candidate.outlierSiteCount == 0 else { return nil }
        guard candidate.positiveSites.count >= 3,
              candidate.negativeSites.count >= 3 else { return nil }
        let argTypeName = predicateSummary
            .flatMap { $0.parameters.count == 1 ? $0.parameters[0].typeText : nil }
            ?? "T"
        let veto = computeVeto(
            summary: predicateSummary,
            predicateArgGeneratable: predicateArgGeneratable
        )
        return EquivalenceClassHint(
            predicateName: candidate.predicateName,
            argTypeName: argTypeName,
            positiveMarker: markerPair.positive,
            negativeMarker: markerPair.negative,
            positiveSiteCount: candidate.positiveSites.count,
            negativeSiteCount: candidate.negativeSites.count,
            predicateVeto: veto,
            suggestedPositiveGenerator: positiveGeneratorExpr(
                argTypeName: argTypeName,
                predicateName: candidate.predicateName
            ),
            suggestedNegativeGenerator: negativeGeneratorExpr(
                argTypeName: argTypeName,
                predicateName: candidate.predicateName
            )
        )
    }

    private static func computeVeto(
        summary: FunctionSummary?,
        predicateArgGeneratable: Bool
    ) -> PredicateVetoReason? {
        guard let summary else { return .predicateArgNotGeneratable }
        if summary.isThrows { return .predicateThrows }
        if summary.isAsync { return .predicateAsync }
        if summary.parameters.count != 1 { return .predicateMultiArg }
        if !predicateArgGeneratable { return .predicateArgNotGeneratable }
        return nil
    }

    private static func positiveGeneratorExpr(argTypeName: String, predicateName: String) -> String {
        "Gen<\(argTypeName)>.gen().filter(\(predicateName))"
    }

    private static func negativeGeneratorExpr(argTypeName: String, predicateName: String) -> String {
        "Gen<\(argTypeName)>.gen().filter { !\(predicateName)($0) }"
    }
}
