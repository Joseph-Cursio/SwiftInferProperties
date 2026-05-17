import Foundation
import Testing
@testable import SwiftInferTemplates

// V1.95 (cycle-92) — tests for the IdentifiedArrayOf<X> /
// IdentifiedArray<ID, X> recognition extension to
// ReferentialIntegrityWitnessDetector. Sibling to the M6 suite to
// keep both files under SwiftLint's type-body length cap.
//
// Modern TCA uses `IdentifiedArrayOf<X>` everywhere instead of bare
// `[X]`; cycle-3 measurement showed referential integrity at 0
// across all 50 TCA 1.25.5 reducers because the v1.94 detector
// only matched array-literal `[X]` collections.

@Suite("ReferentialIntegrityWitnessDetector — V1.95 IdentifiedArrayOf path")
struct ReferentialIntegrityIdentifiedArrayTests {

    @Test("V1.95 — selectedID + IdentifiedArrayOf<X> fires witness")
    func identifiedArrayOfFires() {
        let source = """
        struct AppState {
            var selectedItemID: Item.ID?
            var items: IdentifiedArrayOf<Item>
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
        #expect(witnesses[0].collectionPropertyName == "items")
        #expect(witnesses[0].elementTypeName == "Item")
    }

    @Test("V1.95 — element type from IdentifiedArrayOf<Feature.State> preserves the dotted path")
    func identifiedArrayOfNestedElementType() {
        // TCA's modern convention nests State inside a Reducer.
        // The detector should preserve the dotted element-type
        // text — `Feature.State` — so the rendered predicate can
        // refer to it precisely if/when verification needs the type.
        let source = """
        struct AppState {
            var selectedTodoID: Todo.State.ID?
            var todos: IdentifiedArrayOf<Todo.State>
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
        #expect(witnesses[0].elementTypeName == "Todo.State")
    }

    @Test("V1.95 — explicit IdentifiedArray<ID, X> two-arg form returns the Element (second arg)")
    func identifiedArrayTwoArgForm() {
        let source = """
        struct AppState {
            var selectedItemID: UUID?
            var items: IdentifiedArray<UUID, Item>
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
        #expect(witnesses[0].elementTypeName == "Item")
    }

    @Test("V1.95 — module-prefixed IdentifiedCollections.IdentifiedArrayOf<X> also matches")
    func moduleQualifiedIdentifiedArrayOf() {
        // Real TCA code never uses the module prefix, but the
        // detector stays robust against fully-qualified imports.
        let source = """
        struct AppState {
            var selectedItemID: Item.ID?
            var items: IdentifiedCollections.IdentifiedArrayOf<Item>
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
        #expect(witnesses[0].elementTypeName == "Item")
    }

    @Test("V1.95 — IdentifiedArrayOf<X> + plain [Y] both classified as collections")
    func mixedArrayShapesPairAgainstSameSelected() {
        // A State with both shapes should produce both witnesses
        // via the Cartesian product. The detector treats the two
        // collection forms identically downstream.
        let source = """
        struct AppState {
            var selectedItemID: Item.ID?
            var items: IdentifiedArrayOf<Item>
            var staged: [Item]
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 2)
        let collections = Set(witnesses.map(\.collectionPropertyName))
        #expect(collections == ["items", "staged"])
    }

    @Test("V1.95 — IdentifiedArrayOf<X> alone (no selected pair) produces no witness")
    func identifiedArrayOfAloneFiresNothing() {
        // Referential integrity requires the pair. An
        // IdentifiedArrayOf without a `selected*` Optional in the
        // same State doesn't fire.
        let source = """
        struct AppState {
            var items: IdentifiedArrayOf<Item>
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("V1.95 — IdentifiedArray<ID> (one-arg) returns nil — must be two-arg form")
    func oneArgIdentifiedArrayRejected() {
        // `IdentifiedArray<ID>` alone isn't a valid TCA type — the
        // canonical two-arg form is `IdentifiedArray<ID, Element>`.
        // The detector requires exactly two top-level generic
        // arguments for the two-arg path; a one-arg list returns nil.
        // Without a recognized collection in the State, no witness.
        let source = """
        struct AppState {
            var selectedItemID: UUID?
            var items: IdentifiedArray<UUID>
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("V1.95 — direct helper identifiedArrayElementType returns nil for non-IdentifiedArray shapes")
    func helperReturnsNilForOtherShapes() {
        // Pure-function check of the helper. The implementation
        // is a string-prefix match; the helper should pass through
        // bare `[T]`, `Dictionary<K, V>`, scalars, etc.
        #expect(ReferentialIntegrityExtractor.identifiedArrayElementType("[Item]") == nil)
        #expect(ReferentialIntegrityExtractor.identifiedArrayElementType("Dictionary<String, Int>") == nil)
        #expect(ReferentialIntegrityExtractor.identifiedArrayElementType("Item") == nil)
        #expect(ReferentialIntegrityExtractor.identifiedArrayElementType("Optional<Item>") == nil)
        // Empty inner returns nil (defensive).
        #expect(ReferentialIntegrityExtractor.identifiedArrayElementType("IdentifiedArrayOf<>") == nil)
    }
}
