import Foundation
import PropertyLawKit
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// Self-dogfood road test (`docs/measurements/roadtest-self-dogfood.md` §11.3.2) — extending
// the parity guard from the `TypeShape` mirror to the rest of the persisted
// index.
//
// The failure mode this suite exists for has now bitten three times: **a field
// that is silently dropped somewhere between the scan and the consumer.** Each
// time the symptom was not an error but a *limitation* — a derivation tier that
// quietly stopped firing, reported downstream as `unsupported-carrier` or
// `architectural-coverage-pending`, which a reader files away rather than
// investigates. `IndexedTypeShapeParityPropertyTests` closed one instance
// (`enumCases`). These are the others.
//
// Two mechanisms carry the risk here, and neither announces itself:
//
//   1. **`updated(from:)` rebuilds field-by-field through a defaulted
//      initializer.** Every parameter with a default is a field that can be
//      forgotten and will silently revert on the next re-index rather than fail
//      to compile. This repo already learned that once — the archived note on
//      `InteractionInvariantSuggestion.with(…)` says it outright: "a single site
//      that still rebuilds field-by-field still drops any field it forgets,
//      silently, because the initialiser's parameters have defaults. Mutating a
//      copy cannot." Both index entries still rebuild.
//
//   2. **Hand-written `Codable`.** A field added to the struct and missed in
//      `encode(to:)` reads back as its default with no error at either end.
//
// So the laws below are stated the way that actually catches a forgotten field:
// generate entries whose every column is **non-default and distinguishable**,
// then assert that no column of the result equals its initializer default. A
// dropped field shows up as a default value where neither input had one.
@Suite("Road test — persisted-index projection parity")
struct IndexProjectionParityPropertyTests {

    // MARK: - Generators
    //
    // Every field is populated, and the two sides of a merge are drawn from
    // disjoint alphabets so "came from self" and "came from other" are
    // distinguishable. Optionals are always `.some`: a generator that leaves
    // them nil cannot tell a preserved nil from a dropped field.

    private static func entry(_ tag: String, flags: Bool) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "HASH\(tag)",
            templateName: "template-\(tag)",
            typeName: "Type\(tag)",
            score: flags ? 80 : 40,
            tier: flags ? "Strong" : "Likely",
            primaryFunctionName: "primary\(tag)",
            location: "File\(tag).swift:1",
            decision: "accepted-\(tag)",
            decisionAt: "2026-07-\(tag)T00:00:00Z",
            firstSeenAt: "2026-01-\(tag)T00:00:00Z",
            lastSeenAt: "2026-06-\(tag)T00:00:00Z",
            typeShape: IndexedTypeShape(
                name: "Shape\(tag)",
                kind: .enum,
                inheritedTypes: ["String"],
                hasUserGen: flags,
                enumCases: [IndexedTypeShape.EnumCase(name: "case\(tag)")]
            ),
            secondaryFunctionName: "secondary\(tag)",
            carrierTypeName: "Carrier\(tag)",
            isInstanceMethod: flags,
            isMutatingMethod: flags,
            isNullary: flags,
            returnsSelfType: flags,
            isComputedProperty: flags
        )
    }

    private static func interactionEntry(_ tag: String, score: Int) -> InteractionIndexEntry {
        InteractionIndexEntry(
            identityHash: "IHASH\(tag)",
            family: "idempotence",
            reducerQualifiedName: "Feature\(tag).reduce",
            stateTypeName: "State\(tag)",
            actionTypeName: "Action\(tag)",
            predicate: "predicate\(tag)",
            location: "Feature\(tag).swift:1",
            moduleName: "Module\(tag)",
            score: score,
            tier: "Likely",
            decision: "accepted-\(tag)",
            decisionAt: "2026-07-\(tag)T00:00:00Z",
            firstSeenAt: "2026-01-\(tag)T00:00:00Z",
            lastSeenAt: "2026-06-\(tag)T00:00:00Z"
        )
    }

    private static let tags = ["01", "02", "03"]
    private static let tagGen = Gen.element(of: tags).map { $0! }
    private static let boolGen = Gen.element(of: [true, false]).map { $0! }

    // MARK: - `updated(from:)` — identity from self, everything else from other

    /// **The law that catches a forgotten field.**
    ///
    /// `updated(from:)` rebuilds through an initializer whose optional and
    /// `Bool` parameters all have defaults, so omitting a field compiles and
    /// silently reverts it. Both inputs here carry non-default values in every
    /// column, so any column that comes back as its default was dropped.
    @Test("SemanticIndexEntry.updated never silently defaults a column")
    func semanticEntryUpdatedNeverDefaults() async {
        await propertyCheck(input: Self.tagGen, Self.tagGen, Self.boolGen) { left, right, flags in
            let mine = Self.entry(left, flags: flags)
            let theirs = Self.entry(right, flags: !flags)
            let merged = mine.updated(from: theirs)

            // Nothing may fall back to an initializer default.
            #expect(merged.typeName != nil, "typeName dropped")
            #expect(merged.decision != nil, "decision dropped")
            #expect(merged.decisionAt != nil, "decisionAt dropped")
            #expect(merged.typeShape != nil, "typeShape dropped")
            #expect(merged.secondaryFunctionName != nil, "secondaryFunctionName dropped")
            #expect(merged.carrierTypeName != nil, "carrierTypeName dropped")
            // The five Bool columns were added after the type shipped and all
            // default to `false`; `!flags` on `theirs` makes a dropped one visible.
            #expect(merged.isInstanceMethod == theirs.isInstanceMethod, "isInstanceMethod dropped")
            #expect(merged.isMutatingMethod == theirs.isMutatingMethod, "isMutatingMethod dropped")
            #expect(merged.isNullary == theirs.isNullary, "isNullary dropped")
            #expect(merged.returnsSelfType == theirs.returnsSelfType, "returnsSelfType dropped")
            #expect(merged.isComputedProperty == theirs.isComputedProperty, "isComputedProperty dropped")
        }
    }

    /// The documented split: identity columns survive from the receiver, the
    /// refreshable ones come from the fresh scan. `firstSeenAt` is the
    /// load-bearing one — it anchors §17.2's time-to-adoption metric, and
    /// re-stamping it on every re-index would silently zero that measurement.
    @Test("SemanticIndexEntry.updated keeps identity, takes the rest")
    func semanticEntryUpdatedSplitsCorrectly() async {
        await propertyCheck(input: Self.tagGen, Self.tagGen, Self.boolGen) { left, right, flags in
            let mine = Self.entry(left, flags: flags)
            let theirs = Self.entry(right, flags: !flags)
            let merged = mine.updated(from: theirs)

            #expect(merged.identityHash == mine.identityHash)
            #expect(merged.templateName == mine.templateName)
            #expect(merged.typeName == mine.typeName)
            #expect(merged.firstSeenAt == mine.firstSeenAt, "firstSeenAt must never be re-stamped")
            #expect(merged.carrierTypeName == mine.carrierTypeName)

            #expect(merged.score == theirs.score)
            #expect(merged.tier == theirs.tier)
            #expect(merged.location == theirs.location)
            #expect(merged.lastSeenAt == theirs.lastSeenAt)
            #expect(merged.typeShape == theirs.typeShape)
        }
    }

    /// Refreshing from an identical scan is a no-op — the ordinary re-index
    /// case, and the one that would surface a column being mangled rather than
    /// merely dropped.
    @Test("SemanticIndexEntry.updated from an identical entry is the identity")
    func semanticEntryUpdatedFromSelfIsIdentity() async {
        await propertyCheck(input: Self.tagGen, Self.boolGen) { tag, flags in
            let entry = Self.entry(tag, flags: flags)
            #expect(entry.updated(from: entry) == entry)
        }
    }

    @Test("InteractionIndexEntry.updated never silently defaults a column")
    func interactionEntryUpdatedNeverDefaults() async {
        await propertyCheck(input: Self.tagGen, Self.tagGen, Gen<Int>.int(in: 0...100)) { left, right, score in
            let mine = Self.interactionEntry(left, score: score)
            let theirs = Self.interactionEntry(right, score: score + 1)
            let merged = mine.updated(from: theirs)

            #expect(merged.moduleName != nil, "moduleName dropped")
            #expect(merged.decision != nil, "decision dropped")
            #expect(merged.decisionAt != nil, "decisionAt dropped")

            #expect(merged.identityHash == mine.identityHash)
            #expect(merged.family == mine.family)
            #expect(merged.predicate == mine.predicate)
            #expect(merged.firstSeenAt == mine.firstSeenAt, "firstSeenAt must never be re-stamped")
            #expect(merged.score == theirs.score)
            #expect(merged.lastSeenAt == theirs.lastSeenAt)
        }
    }

    @Test("InteractionIndexEntry.updated from an identical entry is the identity")
    func interactionEntryUpdatedFromSelfIsIdentity() async {
        await propertyCheck(input: Self.tagGen, Gen<Int>.int(in: 0...100)) { tag, score in
            let entry = Self.interactionEntry(tag, score: score)
            #expect(entry.updated(from: entry) == entry)
        }
    }

    // MARK: - Codable round trips, with every column populated

    /// `SemanticIndexEntry` hand-writes both halves of `Codable` across nineteen
    /// fields. A field missed in `encode(to:)` reads back as its default with no
    /// error at either end — the same silence as the `enumCases` omission.
    @Test("SemanticIndexEntry round-trips every column")
    func semanticEntryRoundTrips() async {
        await propertyCheck(input: Self.tagGen, Self.boolGen) { tag, flags in
            let entry = Self.entry(tag, flags: flags)
            let decoded = try? JSONDecoder().decode(
                SemanticIndexEntry.self, from: JSONEncoder().encode(entry)
            )
            #expect(decoded == entry)
            // Named explicitly: whole-value `==` would still pass if the nested
            // shape's own cases were dropped, since both sides would lose them.
            #expect(decoded?.typeShape?.enumCases.isEmpty == false, "nested enumCases dropped")
        }
    }

    @Test("InteractionIndexEntry round-trips every column")
    func interactionEntryRoundTrips() async {
        await propertyCheck(input: Self.tagGen, Gen<Int>.int(in: 0...100)) { tag, score in
            let entry = Self.interactionEntry(tag, score: score)
            let decoded = try? JSONDecoder().decode(
                InteractionIndexEntry.self, from: JSONEncoder().encode(entry)
            )
            #expect(decoded == entry)
        }
    }

    /// The container. Both surfaces plus the shape universe must survive one
    /// hop — this is the file the verify pipeline actually reads.
    @Test("the whole Index round-trips, both surfaces and the shape universe")
    func indexRoundTrips() async {
        await propertyCheck(input: Self.tagGen, Self.boolGen) { tag, flags in
            let index = IndexStore.Index(
                schemaVersion: 5,
                updatedAt: "2026-07-26T00:00:00Z",
                entries: [Self.entry(tag, flags: flags)],
                typeShapes: [
                    "Outer.Kind": IndexedTypeShape(
                        name: "Outer.Kind",
                        kind: .enum,
                        inheritedTypes: ["String"],
                        hasUserGen: false,
                        enumCases: [IndexedTypeShape.EnumCase(name: "`struct`")]
                    )
                ],
                interactionEntries: [Self.interactionEntry(tag, score: 40)]
            )
            let decoded = try? JSONDecoder().decode(
                IndexStore.Index.self, from: JSONEncoder().encode(index)
            )
            #expect(decoded == index)
            #expect(decoded?.typeShapes["Outer.Kind"]?.enumCases.count == 1)
            #expect(decoded?.interactionEntries.count == 1)
        }
    }

    // MARK: - upsert

    /// `firstSeenAt` survives a re-index of the same identity — the metric
    /// anchor again, now through the store rather than the entry.
    @Test("upsert preserves firstSeenAt and refreshes the rest")
    func upsertPreservesFirstSeenAt() async {
        await propertyCheck(input: Self.tagGen, Self.boolGen) { tag, flags in
            let original = Self.entry(tag, flags: flags)
            let existing = IndexStore.Index(
                schemaVersion: 5, updatedAt: "old", entries: [original],
                typeShapes: [:], interactionEntries: []
            )
            var refreshed = Self.entry(tag, flags: !flags)
            refreshed = SemanticIndexEntry(
                identityHash: original.identityHash,
                templateName: refreshed.templateName,
                typeName: refreshed.typeName,
                score: refreshed.score + 1,
                tier: refreshed.tier,
                primaryFunctionName: refreshed.primaryFunctionName,
                location: refreshed.location,
                firstSeenAt: "9999-01-01T00:00:00Z",
                lastSeenAt: refreshed.lastSeenAt
            )
            let merged = IndexStore.upsert([refreshed], into: existing, at: "now")
            #expect(merged.entries.count == 1)
            #expect(merged.entries[0].firstSeenAt == original.firstSeenAt)
            #expect(merged.entries[0].score == refreshed.score)
            #expect(merged.updatedAt == "now")
        }
    }

    /// Historical entries are kept, output is sorted by identity, and shapes
    /// merge with the fresh scan authoritative — all three documented, none
    /// otherwise pinned.
    @Test("upsert keeps history, sorts by identity, and merges shapes")
    func upsertKeepsHistoryAndMergesShapes() {
        let old = Self.entry("01", flags: true)
        let existing = IndexStore.Index(
            schemaVersion: 5, updatedAt: "old", entries: [old],
            typeShapes: [
                "Stale": IndexedTypeShape(
                    name: "Stale", kind: .struct, inheritedTypes: [], hasUserGen: false
                )
            ],
            interactionEntries: []
        )
        let fresh = Self.entry("02", flags: false)
        let merged = IndexStore.upsert(
            [fresh], into: existing, at: "now",
            typeShapes: [
                "Fresh": IndexedTypeShape(
                    name: "Fresh", kind: .enum, inheritedTypes: ["String"], hasUserGen: false,
                    enumCases: [IndexedTypeShape.EnumCase(name: "a")]
                )
            ]
        )
        // History kept.
        #expect(merged.entries.count == 2)
        // Sorted for stable diffs.
        #expect(merged.entries.map(\.identityHash) == merged.entries.map(\.identityHash).sorted())
        // Shapes union rather than replace.
        #expect(merged.typeShapes["Stale"] != nil, "prior shapes must survive")
        #expect(merged.typeShapes["Fresh"]?.enumCases.count == 1)
        // The interaction surface is carried through untouched.
        #expect(merged.interactionEntries.isEmpty)
    }

    /// The two surfaces are independent: upserting one must not disturb the
    /// other. They are parallel arrays in one file, which is exactly the shape
    /// that invites a cross-surface clobber.
    @Test("upserting one surface leaves the other untouched")
    func surfacesAreIndependent() {
        let algebraic = Self.entry("01", flags: true)
        let interaction = Self.interactionEntry("02", score: 40)
        let start = IndexStore.Index(
            schemaVersion: 5, updatedAt: "old", entries: [algebraic],
            typeShapes: [:], interactionEntries: [interaction]
        )
        let afterAlgebraic = IndexStore.upsert([algebraic], into: start, at: "t1")
        #expect(afterAlgebraic.interactionEntries == [interaction])

        let afterInteraction = IndexStore.upsertInteraction(
            [interaction], into: afterAlgebraic, at: "t2"
        )
        #expect(afterInteraction.entries.map(\.identityHash) == [algebraic.identityHash])
        #expect(afterInteraction.interactionEntries.count == 1)
    }
}
