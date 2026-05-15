import Foundation
import Testing
@testable import SwiftInferTemplates

// V2.0 M6 — ReferentialIntegrityWitnessDetector tests. Pure: parse
// a source snippet, assert on detected witnesses.

@Suite("ReferentialIntegrityWitnessDetector — V2.0 M6 selected-ID pair detection")
struct ReferentialIntegrityWitnessDetectorTests {

    // MARK: - Happy paths

    @Test("selectedID + items array → one witness")
    func basicSelectedIDPair() {
        let source = """
        struct AppState {
            var selectedID: UUID?
            var items: [Item]
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
        let witness = witnesses[0]
        #expect(witness.selectedPropertyName == "selectedID")
        #expect(witness.selectedTypeName == "UUID?")
        #expect(witness.collectionPropertyName == "items")
        #expect(witness.elementTypeName == "Item")
    }

    @Test("nested Inbox.State with selectedMessageID + messages → witness")
    func nestedStateWithSelectedMessageID() {
        let source = """
        struct Inbox {
            struct State {
                var selectedMessageID: Message.ID?
                var messages: [Message]
            }
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "Inbox.State",
            in: source
        )
        #expect(witnesses.count == 1)
        #expect(witnesses[0].selectedPropertyName == "selectedMessageID")
        #expect(witnesses[0].elementTypeName == "Message")
    }

    @Test("Optional<UUID> sigil form is recognized alongside T?")
    func optionalGenericForm() {
        let source = """
        struct AppState {
            var selectedItem: Optional<UUID>
            var items: [Item]
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
    }

    @Test("multiple selected-Optionals × multiple arrays → Cartesian product witnesses")
    func cartesianProductWitnesses() {
        let source = """
        struct AppState {
            var selectedItemID: UUID?
            var selectedUserID: UUID?
            var items: [Item]
            var users: [User]
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        // 2 selected-Optionals × 2 arrays = 4 witnesses.
        #expect(witnesses.count == 4)
        let pairs = witnesses.map { ($0.selectedPropertyName, $0.collectionPropertyName) }
        #expect(pairs.contains { $0 == ("selectedItemID", "items") })
        #expect(pairs.contains { $0 == ("selectedItemID", "users") })
        #expect(pairs.contains { $0 == ("selectedUserID", "items") })
        #expect(pairs.contains { $0 == ("selectedUserID", "users") })
    }

    @Test("case-insensitive `selected` prefix match")
    func caseInsensitiveSelectedPrefix() {
        let source = """
        struct AppState {
            var SelectedItemID: UUID?
            var items: [Item]
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
    }

    // MARK: - Negatives

    @Test("selected-Optional without array → no witness")
    func selectedWithoutArray() {
        let source = """
        struct AppState {
            var selectedID: UUID?
            var counter: Int
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("array without selected-Optional → no witness")
    func arrayWithoutSelected() {
        let source = """
        struct AppState {
            var items: [Item]
            var draft: Item?  // optional, but not 'selected'-prefixed
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("non-Optional selected field → no match (name + type both required)")
    func nonOptionalSelectedField() {
        let source = """
        struct AppState {
            var selectedID: UUID
            var items: [Item]
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("dictionary not treated as a collection")
    func dictionaryNotCollection() {
        let source = """
        struct AppState {
            var selectedID: UUID?
            var items: [UUID: Item]
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("computed selected property skipped")
    func computedSelectedSkipped() {
        let source = """
        struct AppState {
            var items: [Item]
            var selectedID: UUID? { items.first?.id }
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("static selected property skipped")
    func staticSelectedSkipped() {
        let source = """
        struct AppState {
            static var selectedID: UUID? = nil
            var items: [Item]
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("target type not found → empty result")
    func targetNotFound() {
        let source = """
        struct OtherState {
            var selectedID: UUID?
            var items: [Item]
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    // MARK: - Helper extractors

    @Test("nameLooksLikeSelected accepts selected-prefixed names case-insensitively")
    func nameLooksLikeSelected() {
        #expect(ReferentialIntegrityExtractor.nameLooksLikeSelected("selected"))
        #expect(ReferentialIntegrityExtractor.nameLooksLikeSelected("selectedID"))
        #expect(ReferentialIntegrityExtractor.nameLooksLikeSelected("SelectedItem"))
        #expect(ReferentialIntegrityExtractor.nameLooksLikeSelected("SELECTEDUSER"))
        #expect(!ReferentialIntegrityExtractor.nameLooksLikeSelected("chosen"))
        #expect(!ReferentialIntegrityExtractor.nameLooksLikeSelected("itemSelected"))
    }
}
