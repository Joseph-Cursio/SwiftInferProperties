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
    ///
    /// **V1.41.A — dominant-pattern classification rule.** Two-layer:
    ///
    /// 1. **Algebraic-collective dominance**: 2+ distinct algebraic
    ///    templates AND their *sum* ≥50% of total → `algebraicStructure`.
    ///    Preserves the v1.36/v1.40 ComplexModule classification (where
    ///    `comm 6 + assoc 6 = 12 of 20 = 60%`).
    ///
    /// 2. **Single-template-dominance**: among the per-template shapes
    ///    (idempotence / dual-style / round-trip) that meet their ≥3
    ///    threshold, the one with the **highest count** wins. This
    ///    reclassifies OrderedSet's 29-entry cluster (dual-style 12 ≥
    ///    idempotence 5) from the pre-v1.41 misclassified
    ///    `algebraicStructure` to the v1.35-cycle-32-finding-intended
    ///    `dualStyleCluster`.
    ///
    /// 3. Catch-all: ≥4 total → `generalCluster`.
    ///
    /// The pre-v1.41 fixed priority order (idempotence before
    /// dual-style before round-trip) is retained as the **tie-breaker**
    /// when two per-template shapes have the same count.
    private struct Candidate {
        let shape: ClusterShape
        let count: Int
        let tieBreakerIndex: Int
    }

    static func classify(
        perTemplateCounts: [String: Int],
        total: Int
    ) -> ClusterShape? {
        // Layer 1: algebraic-collective dominance.
        let algebraicTemplates: Set<String> = [
            "commutativity", "associativity", "identity-element"
        ]
        let algebraicSum = algebraicTemplates.reduce(0) { sum, name in
            sum + (perTemplateCounts[name] ?? 0)
        }
        let presentAlgebraicCount = algebraicTemplates
            .filter { (perTemplateCounts[$0] ?? 0) > 0 }
            .count
        if presentAlgebraicCount >= 2, algebraicSum * 2 >= total {
            return .algebraicStructure
        }
        // Layer 2: per-template most-numerous-above-threshold.
        // `tieBreakerIndex` preserves the pre-v1.41 priority order on
        // equal counts (idempotence 0 > dual-style 1 > round-trip 2).
        let candidates: [Candidate] = [
            Candidate(shape: .idempotenceCluster, count: perTemplateCounts["idempotence"] ?? 0, tieBreakerIndex: 0),
            Candidate(
                shape: .dualStyleCluster,
                count: perTemplateCounts["dual-style-consistency"] ?? 0,
                tieBreakerIndex: 1
            ),
            Candidate(shape: .roundTripCluster, count: perTemplateCounts["round-trip"] ?? 0, tieBreakerIndex: 2)
        ]
        let firing = candidates.filter { $0.count >= 3 }
        if let winner = firing.max(by: { lhs, rhs in
            // Higher count wins; on ties, lower tieBreakerIndex wins.
            if lhs.count != rhs.count { return lhs.count < rhs.count }
            return lhs.tieBreakerIndex > rhs.tieBreakerIndex
        }) {
            return winner.shape
        }
        // Layer 3: general (≥4 total).
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
