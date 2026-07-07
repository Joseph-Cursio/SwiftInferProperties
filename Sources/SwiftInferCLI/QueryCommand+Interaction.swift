import Foundation
import SwiftInferCore

/// V1.141 — which index surface(s) `query` returns. The index holds two
/// disjoint row types (`entries` = algebraic, `interactionEntries` =
/// reducer / MVVM invariant families); `--surface` selects between them.
public enum QuerySurface: String, Equatable, CaseIterable {
    case algebraic
    case interaction
    case all

    /// Lenient parse: an unrecognized string falls back to `.all` and
    /// returns a warning the caller can surface (mirrors the tool's
    /// "never hard-fail a query flag" posture).
    public static func parse(_ raw: String?) -> (surface: Self, warning: String?) {
        guard let raw else { return (.all, nil) }
        if let surface = Self(rawValue: raw) { return (surface, nil) }
        return (
            .all,
            "unrecognized --surface '\(raw)'; expected algebraic|interaction|all — defaulting to all"
        )
    }

    var includesAlgebraic: Bool { self == .algebraic || self == .all }
    var includesInteraction: Bool { self == .interaction || self == .all }
}

/// V1.141 — interaction-surface filtering + rendering for `swift-infer
/// query`, split out of `QueryCommand.swift` to keep that file + the
/// `Query` struct body within SwiftLint's length caps.
extension SwiftInferCommand.Query {

    /// Module-internal for unit tests. The interaction surface shares
    /// `tier` / `decision` / `minScore` with the algebraic filters and
    /// adds `--family`; `--template` / `--type` are algebraic-only and
    /// don't reach here (`runQuery` excludes the interaction surface when
    /// either is set).
    static func applyInteractionFilters(
        _ entries: [InteractionIndexEntry],
        filters: QueryFilters
    ) -> [InteractionIndexEntry] {
        entries.filter { entry in
            if let family = filters.family, entry.family != family { return false }
            if let tier = filters.tier, entry.tier != tier { return false }
            if let minScore = filters.minScore, entry.score < minScore { return false }
            guard matchesInteractionDecision(entry, filter: filters.decision) else { return false }
            return true
        }
    }

    private static func matchesInteractionDecision(
        _ entry: InteractionIndexEntry,
        filter: String?
    ) -> Bool {
        guard let filter else { return true }
        if filter == "untriaged" { return entry.decision == nil }
        return entry.decision == filter
    }

    /// The two rendered lines for one interaction row. Internal (not
    /// private) because `renderCombined` in `QueryCommand.swift` calls it
    /// across the file boundary.
    static func interactionEntryLines(_ entry: InteractionIndexEntry) -> [String] {
        let moduleDisplay = entry.moduleName.map { "\($0)." } ?? ""
        let decisionDisplay = entry.decision ?? "untriaged"
        return [
            "[\(entry.tier) \(entry.score)] "
                + "\(entry.family) | \(moduleDisplay)\(entry.reducerQualifiedName) | "
                + "\(entry.predicate) — \(entry.location)",
            "  decision: \(decisionDisplay)"
                + (entry.decisionAt.map { " (\($0))" } ?? "")
                + ", first seen: \(entry.firstSeenAt), last seen: \(entry.lastSeenAt)"
                + ", identity: \(entry.identityHash)"
        ]
    }
}
