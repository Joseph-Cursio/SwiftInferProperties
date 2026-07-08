import Foundation
import SwiftInferCore

/// V1.143 — author-facing cross-type insights over the SemanticIndex.
///
/// Unlike `docc` (reader-facing, verified-only facts), `insights` opens a
/// **design conversation with the author**: "these N types share an
/// algebraic shape — consider unifying them." That flips the trust bar —
/// inferred `Strong`/`Likely` rows are fair game because a human reviews
/// before acting — but demands a tentative tone (a question, never a
/// directive) and a `Why this might be wrong` line, because a shared
/// *shape* is not a shared *purpose*.
///
/// **Read-only, index-only.** Algebraic structure isn't one index row; it's
/// composed per type from the primitive `associativity` / `commutativity` /
/// `identity-element` template rows. This builder derives a structure label
/// per type and groups across types. It does NOT attempt the call-site
/// "would slot into your merge pipeline" hint — that needs dataflow the
/// index doesn't carry — but it does surface the *adoption gap* it can see
/// (some types in a group already conform to a protocol, others don't).

/// One type in a cross-type structure group.
public struct InsightsMember: Equatable, Sendable {
    public let typeName: String
    /// The binary operation's function name (e.g. `merge(_:_:)`).
    public let operationName: String
    /// The structure's confidence = the weakest contributing property's tier.
    public let tier: String
    /// True when the type already committed to a protocol conformance
    /// (`decision == acceptedAsConformance`) on a structure row.
    public let conforms: Bool

    public init(typeName: String, operationName: String, tier: String, conforms: Bool) {
        self.typeName = typeName
        self.operationName = operationName
        self.tier = tier
        self.conforms = conforms
    }
}

/// A set of types that share one algebraic structure label.
public struct InsightsGroup: Equatable, Sendable {
    public let structure: String
    public let members: [InsightsMember]

    public init(structure: String, members: [InsightsMember]) {
        self.structure = structure
        self.members = members
    }

    /// True when some members already conform and others share the shape but
    /// don't — the actionable "unify them" nudge.
    public var adoptionGap: Bool {
        members.contains(where: \.conforms) && members.contains { !$0.conforms }
    }
}

public enum InsightsBuilder {

    /// The primitive template rows that compose into a binary-op structure.
    static let structureTemplates: Set<String> = ["associativity", "commutativity", "identity-element"]

    // MARK: - Structure composition

    /// Derive the richest algebraic structure a type's template set supports.
    /// `nil` unless the type has an associative binary operation (the
    /// backbone) — idempotence/monotonicity-only types aren't "structures to
    /// unify". Semilattice is deliberately not claimed (the `idempotence`
    /// template is a unary `(T)->T` property, not binary-op idempotence, so
    /// it can't be composed here without a false label).
    public static func structureLabel(for templates: Set<String>) -> String? {
        guard templates.contains("associativity") else { return nil }
        let commutative = templates.contains("commutativity")
        let hasIdentity = templates.contains("identity-element")
        switch (commutative, hasIdentity) {
        case (true, true):   return "commutative monoid"
        case (false, true):  return "monoid"
        case (true, false):  return "commutative semigroup"
        case (false, false): return "semigroup"
        }
    }

    // MARK: - Grouping

    /// Cross-type structure groups with ≥ `minTypes` members, considering
    /// only rows whose tier is in `includeTiers`. Deterministic: members
    /// sorted by type name, groups sorted largest-first then by label.
    public static func groups(
        in index: IndexStore.Index,
        minTypes: Int,
        includeTiers: Set<String>
    ) -> [InsightsGroup] {
        var rowsByType: [String: [SemanticIndexEntry]] = [:]
        for entry in index.entries {
            guard let type = entry.typeName, includeTiers.contains(entry.tier) else { continue }
            rowsByType[type, default: []].append(entry)
        }

        var membersByStructure: [String: [InsightsMember]] = [:]
        for (type, rows) in rowsByType {
            let structureRows = rows.filter { structureTemplates.contains($0.templateName) }
            let templates = Set(structureRows.map(\.templateName))
            guard let structure = structureLabel(for: templates) else { continue }
            let member = InsightsMember(
                typeName: type,
                operationName: operationName(in: structureRows),
                tier: weakestTier(structureRows),
                conforms: structureRows.contains { $0.decision == "acceptedAsConformance" }
            )
            membersByStructure[structure, default: []].append(member)
        }

        return membersByStructure
            .filter { $0.value.count >= minTypes }
            .map { InsightsGroup(structure: $0.key, members: $0.value.sorted { $0.typeName < $1.typeName }) }
            .sorted { lhs, rhs in
                lhs.members.count != rhs.members.count
                    ? lhs.members.count > rhs.members.count
                    : lhs.structure < rhs.structure
            }
    }

    // MARK: - Rendering

    public static func render(_ groups: [InsightsGroup], minTypes: Int, includePossible: Bool) -> String {
        guard !groups.isEmpty else {
            let tierPhrase = includePossible ? "Possible-or-better" : "Strong/Likely"
            return "No cross-type algebraic structure found "
                + "(need ≥\(minTypes) types sharing a \(tierPhrase) shape).\n"
        }
        var lines = ["Cross-type structure  (.swiftinfer/index.json)", ""]
        for group in groups {
            lines += renderGroup(group)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func renderGroup(_ group: InsightsGroup) -> [String] {
        var lines = ["▸ \(group.members.count) types share a \(group.structure) shape"]
        for member in group.members {
            let badge = member.conforms ? "\(member.tier) · conforms" : member.tier
            lines.append("     \(member.typeName)   \(member.operationName)   [\(badge)]")
        }
        lines.append("   → Consider a shared protocol so these compose through common code and their")
        lines.append("     laws are checked once, on every CI run.")
        lines.append("     Why: each exposes \(consequence(for: group.structure)).")
        lines.append("     Why this might be wrong: the domains may be unrelated — a shared protocol")
        lines.append("     only pays off if you actually fold/merge them through shared code.")
        if group.adoptionGap {
            let conforming = group.members.filter(\.conforms).map(\.typeName)
            let notYet = group.members.filter { !$0.conforms }.map(\.typeName)
            let conformVerb = conforming.count == 1 ? "conforms" : "conform"
            let haveVerb = notYet.count == 1 ? "has" : "have"
            lines.append(
                "     Note: \(conforming.joined(separator: ", ")) already \(conformVerb) to a protocol; "
                    + "\(notYet.joined(separator: ", ")) \(haveVerb) the same shape but no conformance."
            )
        }
        return lines
    }

    private static func consequence(for structure: String) -> String {
        switch structure {
        case "commutative monoid":
            return "an associative, order-independent binary operation with an identity element"

        case "monoid":
            return "an associative binary operation with an identity element"

        case "commutative semigroup":
            return "an associative, order-independent binary operation"

        default:
            return "an associative binary operation"
        }
    }

    // MARK: - Helpers

    private static let tierRank: [String: Int] = [
        "Verified": 4, "Strong": 3, "Likely": 2, "Possible": 1, "Advisory": 0, "Suppressed": -1
    ]

    /// The structure is only as trustworthy as its weakest required property.
    private static func weakestTier(_ rows: [SemanticIndexEntry]) -> String {
        rows.min { (tierRank[$0.tier] ?? 0) < (tierRank[$1.tier] ?? 0) }?.tier ?? "Likely"
    }

    /// Canonical associative/commutative operators, preferred as the group's
    /// representative op. Without this, `operationName` would surface an
    /// arbitrary associativity row — which, at `--include-possible`, can be
    /// one of the engine's Possible-tier false positives (e.g. `power` /
    /// `-` / `/` tagged associative), misrepresenting the shared structure.
    /// A BigInt dogfood (2026-07-08) surfaced exactly that: BigUInt's
    /// representative rendered as `power(_:modulus:)` for a "commutative
    /// semigroup". Preferring `+` / `*` shows the operation the structure is
    /// actually about.
    private static let canonicalOperators = ["+", "*"]

    private static func operationName(in rows: [SemanticIndexEntry]) -> String {
        let associative = rows.filter { $0.templateName == "associativity" }
        for symbol in canonicalOperators {
            if let match = associative.first(where: { $0.primaryFunctionName.hasPrefix("\(symbol)(") }) {
                return match.primaryFunctionName
            }
        }
        let fallback = associative.first ?? rows.first { $0.templateName == "commutativity" }
        return fallback?.primaryFunctionName ?? "(operation)"
    }
}
