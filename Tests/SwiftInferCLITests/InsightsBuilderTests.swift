import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// V1.143 — cross-type `insights`: structure composition, grouping, tier
/// gating, adoption-gap detection, and rendering.
@Suite("InsightsBuilder — V1.143 cross-type insights")
struct InsightsBuilderTests {

    private static func row(
        _ type: String,
        _ template: String,
        function: String = "merge(_:_:)",
        tier: String = "Strong",
        decision: String? = nil
    ) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "0x\(type)\(template)",
            templateName: template,
            typeName: type,
            score: 80,
            tier: tier,
            primaryFunctionName: function,
            location: "/x.swift:1",
            decision: decision,
            firstSeenAt: "2026-07-01T00:00:00Z",
            lastSeenAt: "2026-07-01T00:00:00Z"
        )
    }

    private static func index(_ entries: [SemanticIndexEntry]) -> IndexStore.Index {
        IndexStore.Index(updatedAt: "2026-07-01T00:00:00Z", entries: entries)
    }

    private static let allStrongLikely: Set<String> = ["Verified", "Strong", "Likely"]

    // MARK: - structureLabel

    @Test("V1.143 — structure composition from template sets")
    func structureComposition() {
        #expect(InsightsBuilder.structureLabel(for: ["associativity"]) == "semigroup")
        #expect(InsightsBuilder.structureLabel(for: ["associativity", "identity-element"]) == "monoid")
        #expect(
            InsightsBuilder.structureLabel(for: ["associativity", "commutativity"]) == "commutative semigroup"
        )
        #expect(
            InsightsBuilder.structureLabel(
                for: ["associativity", "commutativity", "identity-element"]
            ) == "commutative monoid"
        )
        // No associative backbone → not a structure to unify.
        #expect(InsightsBuilder.structureLabel(for: ["idempotence", "monotonicity"]) == nil)
        #expect(InsightsBuilder.structureLabel(for: ["identity-element"]) == nil)
    }

    // MARK: - grouping

    @Test("V1.143 — three monoid-shaped types form one group of three")
    func threeMonoids() {
        let entries = ["Config", "EventLog", "FeatureFlags"].flatMap { type in
            [Self.row(type, "associativity"), Self.row(type, "identity-element")]
        }
        let groups = InsightsBuilder.groups(in: Self.index(entries), minTypes: 2, includeTiers: Self.allStrongLikely)
        #expect(groups.count == 1)
        #expect(groups.first?.structure == "monoid")
        #expect(groups.first?.members.map(\.typeName) == ["Config", "EventLog", "FeatureFlags"])
    }

    @Test("V1.143 — a lone structured type is excluded by minTypes")
    func loneTypeExcluded() {
        let entries = [Self.row("Config", "associativity"), Self.row("Config", "identity-element")]
        let groups = InsightsBuilder.groups(in: Self.index(entries), minTypes: 2, includeTiers: Self.allStrongLikely)
        #expect(groups.isEmpty)
    }

    @Test("V1.143 — Possible-tier rows are excluded by default tier gate")
    func possibleTierExcluded() {
        // Two types, but one's associativity is only Possible → not counted.
        let entries = [
            Self.row("Config", "associativity"), Self.row("Config", "identity-element"),
            Self.row("EventLog", "associativity", tier: "Possible"), Self.row("EventLog", "identity-element")
        ]
        let groups = InsightsBuilder.groups(in: Self.index(entries), minTypes: 2, includeTiers: Self.allStrongLikely)
        // Only Config qualifies as a monoid → group of 1 → filtered out.
        #expect(groups.isEmpty)
        // Widening to include Possible pulls EventLog in → a group of 2.
        let widened = InsightsBuilder.groups(
            in: Self.index(entries), minTypes: 2,
            includeTiers: ["Verified", "Strong", "Likely", "Possible"]
        )
        #expect(widened.first?.members.count == 2)
    }

    @Test("V1.143 — structure tier is the weakest contributing property")
    func weakestTierWins() {
        let entries = [
            Self.row("Config", "associativity", tier: "Strong"),
            Self.row("Config", "identity-element", tier: "Likely"),
            Self.row("EventLog", "associativity", tier: "Strong"),
            Self.row("EventLog", "identity-element", tier: "Strong")
        ]
        let groups = InsightsBuilder.groups(in: Self.index(entries), minTypes: 2, includeTiers: Self.allStrongLikely)
        let config = groups.first?.members.first { $0.typeName == "Config" }
        #expect(config?.tier == "Likely")   // weakest of Strong+Likely
    }

    @Test("V1.143 — adoptionGap when some conform and others don't")
    func adoptionGap() {
        let entries = [
            Self.row("Config", "associativity", decision: "acceptedAsConformance"),
            Self.row("Config", "identity-element"),
            Self.row("EventLog", "associativity"),
            Self.row("EventLog", "identity-element")
        ]
        let groups = InsightsBuilder.groups(in: Self.index(entries), minTypes: 2, includeTiers: Self.allStrongLikely)
        #expect(groups.first?.adoptionGap == true)
        #expect(groups.first?.members.first { $0.typeName == "Config" }?.conforms == true)
    }

    // MARK: - rendering

    @Test("V1.143 — render includes headline, members, why / why-might-be-wrong, adoption note")
    func renderGroup() {
        let entries = [
            Self.row("Config", "associativity", decision: "acceptedAsConformance"),
            Self.row("Config", "identity-element"),
            Self.row("EventLog", "associativity"),
            Self.row("EventLog", "identity-element")
        ]
        let groups = InsightsBuilder.groups(in: Self.index(entries), minTypes: 2, includeTiers: Self.allStrongLikely)
        let rendered = InsightsBuilder.render(groups, minTypes: 2, includePossible: false)
        #expect(rendered.contains("2 types share a monoid shape"))
        #expect(rendered.contains("Config   merge(_:_:)"))
        #expect(rendered.contains("· conforms"))
        #expect(rendered.contains("Why: each exposes an associative binary operation with an identity element"))
        #expect(rendered.contains("Why this might be wrong"))
        #expect(rendered.contains("Config already conforms to a protocol"))
        #expect(rendered.contains("EventLog has the same shape but no conformance."))
    }

    @Test("V1.143 — empty result renders the guidance line")
    func renderEmpty() {
        let rendered = InsightsBuilder.render([], minTypes: 2, includePossible: false)
        #expect(rendered.contains("No cross-type algebraic structure found"))
        #expect(rendered.contains("Strong/Likely"))
    }

    @Test("V1.143 — representative op prefers a canonical operator (+/*) over an arbitrary associativity row")
    func canonicalOperatorPreferred() {
        // Mirrors the BigInt dogfood: `power` is (falsely) tagged associative
        // and would otherwise be picked as the representative; `+` must win.
        let entries = [
            Self.row("BigUInt", "associativity", function: "power(_:modulus:)"),
            Self.row("BigUInt", "associativity", function: "+(a:b:)"),
            Self.row("BigUInt", "commutativity", function: "+(a:b:)"),
            Self.row("BigInt", "associativity", function: "+(a:b:)"),
            Self.row("BigInt", "commutativity", function: "+(a:b:)")
        ]
        let groups = InsightsBuilder.groups(in: Self.index(entries), minTypes: 2, includeTiers: Self.allStrongLikely)
        let bigUInt = groups.first?.members.first { $0.typeName == "BigUInt" }
        #expect(bigUInt?.operationName == "+(a:b:)")   // not power(_:modulus:)
    }

    @Test("V1.143 — larger groups sort before smaller ones")
    func groupsSortedBySize() {
        // 2 commutative-monoid types + 3 semigroup types.
        var entries = ["A", "B"].flatMap { type in
            [Self.row(type, "associativity"), Self.row(type, "commutativity"), Self.row(type, "identity-element")]
        }
        entries += ["P", "Q", "R"].map { Self.row($0, "associativity") }
        let groups = InsightsBuilder.groups(in: Self.index(entries), minTypes: 2, includeTiers: Self.allStrongLikely)
        #expect(groups.map(\.structure) == ["semigroup", "commutative monoid"])   // 3 before 2
    }
}
