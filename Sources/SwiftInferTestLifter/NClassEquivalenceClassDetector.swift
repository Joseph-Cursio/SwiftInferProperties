import SwiftInferCore

/// TestLifter M13.2 — pure-function detector that decides whether an
/// N-class `PartitionCandidate` from `EquivalenceClassMarkerExtractor`
/// qualifies as a multi-bucket equivalence class, and (when so)
/// returns the `NClassEquivalenceClassHint` the M13.3 accept-flow
/// renderer surfaces.
///
/// Inputs:
/// - `candidate`: the aggregated `(predicateName, markerSet)` partition
///   from M13.2's marker extractor — buckets pre-validated for matched
///   predicate name + matching case literals.
/// - `predicateSummary`: the `FunctionSummary` for the predicate
///   function from production-side scan output — drives the predicate-
///   shape veto checks (throws / async / multi-arg / non-generatable
///   arg type / non-Equatable return type). `nil` when the predicate
///   isn't found in production code (treated as
///   `.predicateArgNotGeneratable`).
/// - `predicateArgGeneratable`: whether the predicate's single argument
///   type is auto-generatable per the M3+ `DerivationStrategist`
///   strategy table.
///
/// Returns an `NClassEquivalenceClassHint` when:
/// 1. `candidate.markerSet != nil` AND `candidate.nClassBucketsByMarker != nil`
///    (carrier-shape guard — M11.1 two-class candidates flow through
///    `PredicateEquivalenceClassDetector` instead).
/// 2. `candidate.outlierSiteCount == 0` (one outlier kills, per PRD §3.5).
/// 3. The number of buckets reaching the per-bucket `≥ 3` threshold
///    is `≥ 3` (an N-class partition with fewer than 3 active buckets
///    isn't N-class — degenerates to 2-class or single-bucket).
///
/// Returns `nil` otherwise. As with M11, the `predicateVeto` field is
/// populated as a non-blocking advisory (the hint still emits with
/// comment-only fallback when a veto fires).
public enum NClassEquivalenceClassDetector {

    /// The per-bucket threshold mirrors M11.1 / M4.3 / M9 / M10 — at
    /// least three sites per bucket so the partition isn't a fluke.
    static let perBucketThreshold = 3

    /// Minimum number of buckets at threshold for the candidate to be
    /// "N-class". Two buckets degenerates to two-class (handled by M11.1);
    /// one bucket isn't a partition.
    static let minActiveBuckets = 3

    public static func detect(
        candidate: PartitionCandidate,
        predicateSummary: FunctionSummary?,
        predicateArgGeneratable: Bool
    ) -> NClassEquivalenceClassHint? {
        guard let markerSet = candidate.markerSet,
              let bucketsByMarker = candidate.nClassBucketsByMarker else {
            return nil
        }
        guard candidate.outlierSiteCount == 0 else { return nil }
        let activeMarkers = markerSet.markers.filter { marker in
            (bucketsByMarker[marker]?.count ?? 0) >= Self.perBucketThreshold
        }
        guard activeMarkers.count >= Self.minActiveBuckets else { return nil }
        let argTypeName = predicateSummary
            .flatMap { $0.parameters.count == 1 ? $0.parameters[0].typeText : nil }
            ?? "T"
        let returnTypeName = predicateSummary?.returnTypeText ?? "<unknown>"
        let veto = computeVeto(
            summary: predicateSummary,
            predicateArgGeneratable: predicateArgGeneratable
        )
        let siteCounts = Dictionary(uniqueKeysWithValues: activeMarkers.map { marker in
            (marker, bucketsByMarker[marker]?.count ?? 0)
        })
        let generators = Dictionary(uniqueKeysWithValues: activeMarkers.map { marker in
            (marker, generatorExpr(
                argTypeName: argTypeName,
                predicateName: candidate.predicateName,
                marker: marker
            ))
        })
        return NClassEquivalenceClassHint(
            predicateName: candidate.predicateName,
            argTypeName: argTypeName,
            returnTypeName: returnTypeName,
            markerSetName: markerSet.name,
            markers: activeMarkers,
            siteCountsByMarker: siteCounts,
            predicateVeto: veto,
            suggestedGeneratorsByMarker: generators
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
        if !returnTypeIsLikelyEquatable(summary.returnTypeText) {
            return .predicateReturnNotEquatable
        }
        return nil
    }

    /// M13 plan OD #3 — proxy for the full `Equatable` conformance check
    /// (which would need SemanticIndex). v1.x recognizes:
    /// - Stdlib types known to be Equatable: `Int`, `String`, `Bool`,
    ///   `UInt*`, `Int*`, `Float`, `Double`, `Character`, `Substring`.
    /// - Identifier-form return types (presumed Equatable enums when
    ///   declared in the project) — accepted optimistically; the
    ///   compile-time check happens when the user wires the suggested
    ///   generator into a runnable property test.
    /// - Optionals over the above.
    ///
    /// Rejects: function types `(_) -> _`, generic placeholders like
    /// `T` / `U`, tuples, arrays, dictionaries, sets — any compound or
    /// abstract shape we can't statically verify is Equatable without
    /// SemanticIndex.
    private static func returnTypeIsLikelyEquatable(_ returnTypeText: String?) -> Bool {
        guard let raw = returnTypeText?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty else {
            return false
        }
        let stripped = raw.hasSuffix("?") ? String(raw.dropLast()) : raw
        if stripped.contains("->") { return false }
        if stripped.hasPrefix("(") || stripped.hasPrefix("[") { return false }
        if stripped == "T" || stripped == "U" || stripped == "V" { return false }
        // Identifier-only check — must be a legal Swift type name.
        return stripped.allSatisfy { character in
            character.isLetter || character.isNumber || character == "_" || character == "."
        } && !stripped.isEmpty
    }

    private static func generatorExpr(
        argTypeName: String,
        predicateName: String,
        marker: String
    ) -> String {
        let caseLiteral = lowercaseFirst(marker)
        return "Gen<\(argTypeName)>.gen().filter { \(predicateName)($0) == .\(caseLiteral) }"
    }

    /// Marker text in vocabulary is conventionally Title-cased
    /// (`"Small"`); Swift enum cases are lowercase-first (`.small`).
    /// Lowercase the leading character so the suggested generator
    /// matches the typical Swift convention. The user reads the
    /// rendered comment block + tweaks if their actual case spelling
    /// differs.
    private static func lowercaseFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }
}
