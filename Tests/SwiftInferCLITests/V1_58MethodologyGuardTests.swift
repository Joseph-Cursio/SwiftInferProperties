import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

// V1.58.B — methodology guard for `GenericBindingResolver.curatedBindings`.
//
// **Why this exists.** Cycle-50 measurement (`docs/calibration-cycle-50-
// findings.md`) revealed that V1.52.C's 4 `<Type>.Index` binding keys
// (e.g. `ChunkedByCollection.Index`) never matched any indexer-produced
// carrier name in the cycle-27 fixture — they were dead code, latent
// for an entire release cycle. V1.51.B had the same shape: dual-style
// pair entries that didn't match cycle-27's actual function names.
//
// This guard asserts every `curatedBindings` key appears at least once
// in the cycle-27 fixture, either as a top-level `typeName` or as a
// `typeShape.storedMembers[].typeName`. Adding a binding key that
// matches nothing fails this test pre-merge.
//
// **Why fixture-coupled.** The cycle-27 fixture is the v1.29-frozen
// (later v1.57-frozen at 103 picks) measurement baseline. Bindings
// that don't match anything in the baseline are speculative — they
// either anticipate future indexer changes (legitimate but should be
// flagged) or are wrong about the indexer's output format (the
// V1.51.B / V1.52.C pattern).
//
// **Escape hatch**: a binding key can be added to
// `intentionallyUnmatchedKeys` below if it's deliberately speculative
// (e.g., for a future indexer output format the cycle-27 fixture
// doesn't yet contain). v1.58 ships with this set empty.

@Suite("V1.58.B — GenericBindingResolver methodology guard")
struct V158MethodologyGuardTests {

    /// Path to the cycle-27 fixture's merged index.
    private static let fixtureIndexPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Tests/SwiftInferCLITests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
        .appendingPathComponent("fixtures/cycle27-surface/.swiftinfer/index.json")

    /// Bindings that are deliberately speculative (don't yet match any
    /// cycle-27 carrier name but anticipate future indexer output).
    ///
    /// **V1.58.B findings**: the V1.47.D protocol-extension bindings
    /// (`Self.Index` / `Self.Element` / `Base.Element` / `Iterator.Element`)
    /// don't match anything in cycle-27. They were added preemptively
    /// for "the `Self.Index` / `Self.Element` shape that protocol
    /// extensions on Collection / Sequence produce" (per the
    /// V1.47.D code comment) but no cycle-27 indexer entry surfaces
    /// these as stored-member type names. Keeping them as escape-hatch
    /// entries lets the V1.47.D pre-emption stand without polluting
    /// the methodology guard's signal — if a future cycle adds a pick
    /// whose TypeShape's storedMembers include `Self.Element`, those
    /// will match and the entry can be removed from here.
    ///
    /// **`Base.Index` (cycle 148)**: previously matched via cycle-27
    /// `ChunkedByCollection` picks' stored-member type-name, so it was NOT in
    /// the escape hatch. Cycle 148's Lever A non-public/SPI discovery filter
    /// dropped that pick (its method was internal-sourced), so `Base.Index`
    /// no longer matches any surfaced carrier. The binding itself is still a
    /// legitimate generic-index resolution (`Base.Index → Int` for collection
    /// generics), so it moves here rather than being removed — exactly the
    /// "pick removed → move to escape hatch" path this guard anticipates.
    private static let intentionallyUnmatchedKeys: Set<String> = [
        "Self.Index",
        "Self.Element",
        "Base.Element",
        "Iterator.Element",
        "Base.Index"
    ]

    @Test("every curatedBindings key matches a cycle-27 carrier name or stored-member type-name")
    func everyBindingMatchesAFixtureCarrier() throws {
        let data = try Data(contentsOf: Self.fixtureIndexPath)
        let store = try JSONDecoder().decode(IndexStore.Index.self, from: data)
        let knownCarrierNames = Self.collectCarrierNames(in: store.entries)
        let bindingKeys = Set(GenericBindingResolver.curatedBindings.keys)
        let unmatched = bindingKeys
            .subtracting(knownCarrierNames)
            .subtracting(Self.intentionallyUnmatchedKeys)
        if !unmatched.isEmpty {
            let sortedKeys = unmatched.sorted().joined(separator: ", ")
            let message = """
            These curatedBindings keys don't match any cycle-27 carrier \
            or stored-member type-name (latent dead bindings): [\(sortedKeys)]. \
            Either remove them, or add to intentionallyUnmatchedKeys with \
            a comment explaining why they're speculative.
            """
            Issue.record(Comment(rawValue: message))
        }
        #expect(unmatched.isEmpty)
    }

    @Test("intentionallyUnmatchedKeys are themselves keys in curatedBindings (no orphan entries)")
    func intentionalEscapeHatchesAreActualBindings() {
        let bindingKeys = Set(GenericBindingResolver.curatedBindings.keys)
        for key in Self.intentionallyUnmatchedKeys where !bindingKeys.contains(key) {
            Issue.record(
                """
                intentionallyUnmatchedKeys lists '\(key)' but it's not in \
                curatedBindings — the escape hatch is stale.
                """
            )
        }
    }

    // MARK: - Helpers

    /// Collect all distinct carrier-name strings from the fixture:
    /// top-level `typeName` values + `typeShape.storedMembers[].typeName`
    /// values. The latter is needed for bindings like `Base.Index → Int`
    /// which target stored-member types, not top-level carriers.
    private static func collectCarrierNames(in entries: [SemanticIndexEntry]) -> Set<String> {
        var carriers: Set<String> = []
        for entry in entries {
            if let typeName = entry.typeName {
                carriers.insert(typeName)
            }
            if let shape = entry.typeShape {
                for member in shape.storedMembers {
                    carriers.insert(member.typeName)
                }
            }
        }
        return carriers
    }
}
