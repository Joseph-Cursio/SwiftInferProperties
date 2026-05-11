import Foundation
import SwiftInferCore

/// V1.35.A — carrier-aware refactor-suggestion analyzer (PRD §20.1
/// follow-up). Groups SemanticIndex entries by `typeName` and
/// classifies the per-type cluster into a named shape that drives
/// curated user-facing refactor suggestions.
///
/// Read-only over the SemanticIndex output — no source modification,
/// no inference changes. Consumed by `swift-infer suggest-refactors`
/// (V1.35.B).

/// One per (typeName, cluster-shape) row.
public struct RefactorCluster: Sendable, Equatable {

    /// Carrier type name from `SemanticIndexEntry.typeName`. Never
    /// nil — the analyzer filters nil-carrier entries out before
    /// building clusters.
    public let typeName: String

    /// Number of suggestions in this type's cluster.
    public let totalSuggestionCount: Int

    /// templateName → count. Empty templates (count 0) are not
    /// included.
    public let perTemplateCounts: [String: Int]

    /// Classification — drives the curated per-shape suggestion text.
    public let shape: ClusterShape

    /// Up to 5 representative function names from the cluster's
    /// suggestions, in score-descending order. Helps the user
    /// recognize which APIs the cluster refers to.
    public let representativeFunctions: [String]

    public init(
        typeName: String,
        totalSuggestionCount: Int,
        perTemplateCounts: [String: Int],
        shape: ClusterShape,
        representativeFunctions: [String]
    ) {
        self.typeName = typeName
        self.totalSuggestionCount = totalSuggestionCount
        self.perTemplateCounts = perTemplateCounts
        self.shape = shape
        self.representativeFunctions = representativeFunctions
    }
}

/// 5-shape taxonomy. Classification is **priority-ordered**: more-
/// specific shapes win when multiple match. The `generalCluster`
/// catch-all surfaces high-suggestion-count types that don't match
/// any named pattern.
public enum ClusterShape: String, Sendable, Equatable, CaseIterable {

    /// 2+ distinct templates in `{commutativity, associativity,
    /// identity-element}` on the same type. Suggests the type
    /// already behaves like a kit-defined algebra (Semigroup /
    /// Monoid / CommutativeMonoid / Semilattice / Semiring) and could
    /// conform formally so SwiftPropertyLaws verifies the laws on
    /// every CI run.
    case algebraicStructure

    /// 3+ idempotence suggestions (lifted + non-lifted combined) on
    /// the same type. Suggests a cluster of "normalize this value"
    /// mutators worth documenting + treating uniformly.
    case idempotenceCluster

    /// 3+ dual-style-consistency (form/non-form pair) suggestions on
    /// the same type. Suggests the type is a SetAlgebra-shape /
    /// similar mutating-pair-rich abstraction.
    case dualStyleCluster

    /// 3+ round-trip pair suggestions on the same type. Suggests the
    /// type is a codec / serialization-bearing structure worth
    /// surfacing via a Codec-shaped abstraction.
    case roundTripCluster

    /// Catch-all: 4+ suggestions of any mix on the same type but
    /// outside the named shapes above. Worth surfacing as "this type
    /// has a lot of inferred properties" without prescribing a
    /// specific refactor.
    case generalCluster
}

public enum RefactorClusterAnalyzer {

    /// Group `entries` by `typeName`, classify each per-type cluster,
    /// and return the qualifying clusters sorted by
    /// `totalSuggestionCount` descending.
    ///
    /// Entries with `typeName == nil` are filtered out (free
    /// functions don't cluster by carrier).
    public static func analyze(_ entries: [SemanticIndexEntry]) -> [RefactorCluster] {
        let grouped = Dictionary(grouping: entries.filter { $0.typeName != nil }) { entry in
            entry.typeName!
        }
        var clusters: [RefactorCluster] = []
        for (typeName, typeEntries) in grouped {
            let perTemplateCounts = countByTemplate(typeEntries)
            guard let shape = classify(perTemplateCounts: perTemplateCounts, total: typeEntries.count) else {
                continue
            }
            // Score-descending sort, then pick up to 5 representative
            // function display names.
            let representatives = typeEntries
                .sorted { $0.score > $1.score }
                .prefix(5)
                .map(\.primaryFunctionName)
            clusters.append(RefactorCluster(
                typeName: typeName,
                totalSuggestionCount: typeEntries.count,
                perTemplateCounts: perTemplateCounts,
                shape: shape,
                representativeFunctions: Array(representatives)
            ))
        }
        return clusters.sorted { $0.totalSuggestionCount > $1.totalSuggestionCount }
    }

    /// Module-internal so V1.35.A unit tests can drive classification
    /// directly without building fixture entry lists.
    static func classify(
        perTemplateCounts: [String: Int],
        total: Int
    ) -> ClusterShape? {
        // Priority 1: algebraic structure (2+ distinct algebraic templates).
        let algebraic: Set<String> = [
            "commutativity", "associativity", "identity-element"
        ]
        let presentAlgebraic = algebraic.filter { (perTemplateCounts[$0] ?? 0) > 0 }
        if presentAlgebraic.count >= 2 {
            return .algebraicStructure
        }
        // Priority 2: idempotence cluster (≥3 idempotence suggestions).
        if (perTemplateCounts["idempotence"] ?? 0) >= 3 {
            return .idempotenceCluster
        }
        // Priority 3: dual-style cluster (≥3 dual-style suggestions).
        if (perTemplateCounts["dual-style-consistency"] ?? 0) >= 3 {
            return .dualStyleCluster
        }
        // Priority 4: round-trip cluster (≥3 round-trip pairs).
        if (perTemplateCounts["round-trip"] ?? 0) >= 3 {
            return .roundTripCluster
        }
        // Priority 5: general (≥4 total).
        if total >= 4 {
            return .generalCluster
        }
        return nil
    }

    private static func countByTemplate(_ entries: [SemanticIndexEntry]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in entries {
            counts[entry.templateName, default: 0] += 1
        }
        return counts
    }
}
