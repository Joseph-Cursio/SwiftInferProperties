import Foundation
@testable import SwiftInferTemplates
import Testing

// V2.0 M4.B — ConservationWitnessDetector tests. Pure: parse a
// source snippet, look for a State type, assert on the resulting
// ConservationWitness list. Each test names the heuristic it
// exercises so calibration cycles can read which detection rule
// holds it together.

@Suite("ConservationWitnessDetector — V2.0 M4.B witness detection")
struct ConservationWitnessDetectorTests {

    // MARK: - Detection happy path

    @Test("nested `Inbox.State` with count + items pair → one witness")
    func nestedStateWithCountAndItems() {
        let source = """
        struct Inbox {
            struct State {
                var count: Int
                var items: [String]
            }
        }
        """
        let witnesses = ConservationWitnessDetector.detect(
            stateTypeName: "Inbox.State",
            in: source
        )
        #expect(witnesses.count == 1)
        let witness = witnesses[0]
        #expect(witness.aggregatePropertyName == "count")
        #expect(witness.aggregateTypeName == "Int")
        #expect(witness.collectionPropertyName == "items")
        #expect(witness.elementTypeName == "String")
    }

    @Test("top-level State struct → witness fires the same way")
    func topLevelState() {
        let source = """
        struct AppState {
            var entryCount: Int
            var entries: [Entry]
        }
        """
        let witnesses = ConservationWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
        #expect(witnesses[0].aggregatePropertyName == "entryCount")
        #expect(witnesses[0].elementTypeName == "Entry")
    }

    @Test("multiple count + array pairs produce Cartesian-product witnesses")
    func cartesianProduct() {
        let source = """
        struct AppState {
            var itemCount: Int
            var tagCount: Int
            var items: [String]
            var tags: [String]
        }
        """
        let witnesses = ConservationWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        // 2 count-shaped aggregates × 2 arrays = 4 witnesses.
        #expect(witnesses.count == 4)
    }

    // MARK: - Negatives

    @Test("computed-property aggregate is skipped (no invariant to verify)")
    func computedAggregateIsSkipped() {
        let source = """
        struct AppState {
            var items: [String]
            var count: Int { items.count }
        }
        """
        let witnesses = ConservationWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("static count is skipped — doesn't participate in state conservation")
    func staticCountIsSkipped() {
        let source = """
        struct AppState {
            static var count: Int = 0
            var items: [String]
        }
        """
        let witnesses = ConservationWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("floating-point aggregate is skipped per PRD §5.2 counter-signal")
    func floatingPointAggregateIsSkipped() {
        let source = """
        struct AppState {
            var count: Double
            var items: [String]
        }
        """
        let witnesses = ConservationWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("dictionary literal is not treated as a collection element")
    func dictionaryIsNotArray() {
        let source = """
        struct AppState {
            var count: Int
            var items: [String: Int]
        }
        """
        let witnesses = ConservationWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("non-count-shaped name is not treated as an aggregate")
    func nonCountNameIsNotAggregate() {
        let source = """
        struct AppState {
            var total: Int  // not count-shaped
            var items: [String]
        }
        """
        let witnesses = ConservationWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("target type not found → empty result")
    func targetNotFound() {
        let source = """
        struct OtherType {
            var count: Int
            var items: [String]
        }
        """
        let witnesses = ConservationWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    // MARK: - Helper extractors

    @Test("nameLooksLikeCount matches count / Count / numCount-style names")
    func nameLooksLikeCount() {
        #expect(ConservationWitnessExtractor.nameLooksLikeCount("count"))
        #expect(ConservationWitnessExtractor.nameLooksLikeCount("itemCount"))
        #expect(ConservationWitnessExtractor.nameLooksLikeCount("Count"))
        #expect(ConservationWitnessExtractor.nameLooksLikeCount("entryCountTotal"))
        #expect(!ConservationWitnessExtractor.nameLooksLikeCount("total"))
        #expect(!ConservationWitnessExtractor.nameLooksLikeCount("size"))
    }

    @Test("typeLooksLikeIntegerCount accepts integer types, rejects floats / strings")
    func typeLooksLikeIntegerCount() {
        #expect(ConservationWitnessExtractor.typeLooksLikeIntegerCount("Int"))
        #expect(ConservationWitnessExtractor.typeLooksLikeIntegerCount("UInt"))
        #expect(ConservationWitnessExtractor.typeLooksLikeIntegerCount("Int32"))
        #expect(ConservationWitnessExtractor.typeLooksLikeIntegerCount("Swift.Int"))
        #expect(!ConservationWitnessExtractor.typeLooksLikeIntegerCount("Double"))
        #expect(!ConservationWitnessExtractor.typeLooksLikeIntegerCount("Float"))
        #expect(!ConservationWitnessExtractor.typeLooksLikeIntegerCount("Decimal"))
        #expect(!ConservationWitnessExtractor.typeLooksLikeIntegerCount("String"))
    }

    @Test("arrayElementType extracts the bracketed element type")
    func arrayElementType() {
        #expect(ConservationWitnessExtractor.arrayElementType("[String]") == "String")
        #expect(ConservationWitnessExtractor.arrayElementType("[Inbox.Message]") == "Inbox.Message")
        #expect(ConservationWitnessExtractor.arrayElementType("[Result<Int, Error>]") == "Result<Int, Error>")
        // Dictionary literal — has top-level colon, returns nil.
        #expect(ConservationWitnessExtractor.arrayElementType("[String: Int]") == nil)
        // Not bracketed.
        #expect(ConservationWitnessExtractor.arrayElementType("String") == nil)
        #expect(ConservationWitnessExtractor.arrayElementType("Array<Int>") == nil)
    }
}
