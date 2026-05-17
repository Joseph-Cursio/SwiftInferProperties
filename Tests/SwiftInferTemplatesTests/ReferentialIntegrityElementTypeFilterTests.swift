import Foundation
import Testing
@testable import SwiftInferTemplates

// V1.104 (cycle-101a Finding C fix) — regression tests for the
// element-type filter in ReferentialIntegrityExtractor.extract.
// Pure: parse a source snippet, assert on detected witnesses.

@Suite("ReferentialIntegrityWitnessDetector — V1.104 element-type filter")
struct RefIntElementTypeFilterTests {

    // MARK: - Filtering

    @Test func selectedMessageIDPairsWithMessagesOnly() {
        // The HandRolled MessageListReducer case from cycle-99
        // Finding C. Pre-fix: 2 witnesses (selectedMessageID paired
        // with both messages and drafts). Post-fix: 1 witness
        // (drafts pairing filtered because Draft != Message).
        let source = """
        struct AppState {
            var selectedMessageID: Message.ID?
            var messages: [Message]
            var drafts: [Draft]
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
        #expect(witnesses[0].selectedPropertyName == "selectedMessageID")
        #expect(witnesses[0].collectionPropertyName == "messages")
        #expect(witnesses[0].elementTypeName == "Message")
    }

    @Test func selectedItemPairsWithItemsCollection() {
        // No "ID" suffix — `selectedItem` → implied "Item".
        let source = """
        struct AppState {
            var selectedItem: Item?
            var items: [Item]
            var folders: [Folder]
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

    @Test func multipleSelectedFieldsEachPairWithCompatibleCollection() {
        // Two selected fields each independently filter to their
        // matching collection — no cross-pairing.
        let source = """
        struct AppState {
            var selectedMessageID: Message.ID?
            var selectedDraftID: Draft.ID?
            var messages: [Message]
            var drafts: [Draft]
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 2)
        let pairs = Set(witnesses.map {
            "\($0.selectedPropertyName)→\($0.collectionPropertyName)"
        })
        #expect(pairs == [
            "selectedMessageID→messages",
            "selectedDraftID→drafts"
        ])
    }

    // MARK: - Fallback (no extractable core)

    @Test func bareSelectedFallsBackToCartesian() {
        // `selected` has no extractable core after stripping the
        // prefix → fallback to Cartesian. Both collections pair.
        let source = """
        struct AppState {
            var selected: UUID?
            var messages: [Message]
            var drafts: [Draft]
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 2)
        let collectionNames = Set(witnesses.map(\.collectionPropertyName))
        #expect(collectionNames == ["messages", "drafts"])
    }

    @Test func selectedIDFallsBackToCartesian() {
        // `selectedID` — core after stripping prefix is `ID`,
        // after stripping suffix is empty → fallback.
        let source = """
        struct AppState {
            var selectedID: UUID?
            var messages: [Message]
            var drafts: [Draft]
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 2)
    }

    // MARK: - Type-normalization edge cases

    @Test func qualifiedElementTypeStripsModulePrefix() {
        // `selectedMessageID` → implied "Message". Collection
        // element extracted as `Inbox.Message`. Normalization strips
        // the qualifier → match.
        let source = """
        struct AppState {
            var selectedMessageID: Inbox.Message.ID?
            var messages: [Inbox.Message]
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
        #expect(witnesses[0].elementTypeName == "Inbox.Message")
    }

    @Test func caseInsensitiveMatch() {
        // Implied core casing might differ from element type
        // casing if the user follows non-canonical conventions.
        // Match should be case-insensitive.
        let source = """
        struct AppState {
            var selectedmessageid: Message.ID?
            var messages: [Message]
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
    }

    @Test func noPairingWhenNoCollectionMatches() {
        // `selectedFooID` with no `[Foo]` collection — fallback
        // does NOT apply (implied core is extractable), so no
        // witnesses fire. This is the intended Finding C behavior:
        // suppress impossible pairings entirely rather than
        // emitting a malformed witness.
        let source = """
        struct AppState {
            var selectedFooID: Foo.ID?
            var messages: [Message]
            var drafts: [Draft]
        }
        """
        let witnesses = ReferentialIntegrityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    // MARK: - impliedElementType direct unit tests

    @Test func impliedElementTypeStripsPrefixAndIDSuffix() {
        #expect(
            ReferentialIntegrityExtractor.impliedElementType(
                fromSelectedName: "selectedMessageID"
            ) == "Message"
        )
        #expect(
            ReferentialIntegrityExtractor.impliedElementType(
                fromSelectedName: "selectedItemId"
            ) == "Item"
        )
        #expect(
            ReferentialIntegrityExtractor.impliedElementType(
                fromSelectedName: "selectedFolder"
            ) == "Folder"
        )
    }

    @Test func impliedElementTypeReturnsNilForBareForms() {
        #expect(
            ReferentialIntegrityExtractor.impliedElementType(
                fromSelectedName: "selected"
            ) == nil
        )
        #expect(
            ReferentialIntegrityExtractor.impliedElementType(
                fromSelectedName: "selectedID"
            ) == nil
        )
        #expect(
            ReferentialIntegrityExtractor.impliedElementType(
                fromSelectedName: "selectedId"
            ) == nil
        )
    }

    @Test func impliedElementTypeReturnsNilWhenSelectedPrefixMissing() {
        // The pairing-time call sites only ever pass names that
        // already match `nameLooksLikeSelected`. This is a
        // belt-and-suspenders unit test.
        #expect(
            ReferentialIntegrityExtractor.impliedElementType(
                fromSelectedName: "currentMessageID"
            ) == nil
        )
    }
}
