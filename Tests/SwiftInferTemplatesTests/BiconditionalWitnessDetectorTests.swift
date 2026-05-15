import Foundation
import Testing
@testable import SwiftInferTemplates

// V2.0 M7 — BiconditionalWitnessDetector tests. Pure: parse a
// source snippet, assert on detected witnesses.

@Suite("BiconditionalWitnessDetector — V2.0 M7 Bool + Optional pair detection")
struct BiconditionalWitnessDetectorTests {

    // MARK: - Happy paths

    @Test("isLoading + activeTask Optional → one witness")
    func basicLoadingTaskPair() {
        let source = """
        struct AppState {
            var isLoading: Bool
            var activeTask: Task<Void, Never>?
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
        let witness = witnesses[0]
        #expect(witness.boolPropertyName == "isLoading")
        #expect(witness.optionalPropertyName == "activeTask")
    }

    @Test("isShowingSheet + sheet Optional → witness")
    func showingSheetPair() {
        let source = """
        struct AppState {
            var isShowingSheet: Bool
            var sheet: Sheet?
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
        #expect(witnesses[0].boolPropertyName == "isShowingSheet")
    }

    @Test("isPresenting / isActive / isFetching / isRefreshing all match")
    func variousBoolPatterns() {
        let source = """
        struct AppState {
            var isPresenting: Bool
            var data: Data?
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
        // Also test isActive
        let activeSource = """
        struct A { var isActive: Bool; var task: Task<Void, Never>? }
        """
        #expect(BiconditionalWitnessDetector.detect(stateTypeName: "A", in: activeSource).count == 1)
        // isFetching
        let fetchSource = """
        struct B { var isFetching: Bool; var result: Result<Int, Error>? }
        """
        #expect(BiconditionalWitnessDetector.detect(stateTypeName: "B", in: fetchSource).count == 1)
        // isRefreshing
        let refreshSource = """
        struct C { var isRefreshing: Bool; var cache: Cache? }
        """
        #expect(BiconditionalWitnessDetector.detect(stateTypeName: "C", in: refreshSource).count == 1)
    }

    @Test("Cartesian product — multiple Bools × multiple Optionals")
    func cartesianProduct() {
        let source = """
        struct AppState {
            var isLoading: Bool
            var isShowingDetail: Bool
            var activeTask: Task<Void, Never>?
            var draft: Item?
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        // 2 bools × 2 optionals = 4 witnesses
        #expect(witnesses.count == 4)
    }

    @Test("nested Inbox.State with isLoading + task → witness")
    func nestedStateWithLoading() {
        let source = """
        struct Inbox {
            struct State {
                var isLoadingMessages: Bool
                var fetchTask: Task<Void, Never>?
            }
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "Inbox.State",
            in: source
        )
        #expect(witnesses.count == 1)
        #expect(witnesses[0].boolPropertyName == "isLoadingMessages")
    }

    // MARK: - Negatives

    @Test("Bool without matching name pattern → not a flag")
    func unmatchedBoolName() {
        let source = """
        struct AppState {
            var isEnabled: Bool
            var data: Data?
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("Bool with matching name but no Optional → no witness")
    func boolWithoutOptional() {
        let source = """
        struct AppState {
            var isLoading: Bool
            var counter: Int
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("Optional but no matching Bool → no witness")
    func optionalWithoutBool() {
        let source = """
        struct AppState {
            var task: Task<Void, Never>?
            var counter: Int
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("computed properties skipped")
    func computedSkipped() {
        let source = """
        struct AppState {
            var task: Task<Void, Never>?
            var isLoading: Bool { task != nil }
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("static properties skipped")
    func staticSkipped() {
        let source = """
        struct AppState {
            static var isLoading: Bool = false
            var task: Task<Void, Never>?
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("case-sensitive — lowercase 'loading' does not match")
    func caseSensitive() {
        let source = """
        struct AppState {
            var loading: Bool
            var task: Task<Void, Never>?
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    // MARK: - Helper extractors

    @Test("isBoolType matches Bool / Swift.Bool")
    func isBoolType() {
        #expect(BiconditionalExtractor.isBoolType("Bool"))
        #expect(BiconditionalExtractor.isBoolType("Swift.Bool"))
        #expect(!BiconditionalExtractor.isBoolType("Int"))
        #expect(!BiconditionalExtractor.isBoolType("Bool?"))
    }

    @Test("isOptionalType matches T? / Optional<T>")
    func isOptionalType() {
        #expect(BiconditionalExtractor.isOptionalType("Task<Void, Never>?"))
        #expect(BiconditionalExtractor.isOptionalType("Optional<Int>"))
        #expect(!BiconditionalExtractor.isOptionalType("Bool"))
        #expect(!BiconditionalExtractor.isOptionalType("[Item]"))
    }

    @Test("nameLooksLikeBiconditionalFlag matches case-sensitive substrings")
    func nameLooksLikeFlag() {
        #expect(BiconditionalExtractor.nameLooksLikeBiconditionalFlag("isLoading"))
        #expect(BiconditionalExtractor.nameLooksLikeBiconditionalFlag("isShowingSheet"))
        #expect(BiconditionalExtractor.nameLooksLikeBiconditionalFlag("isPresenting"))
        #expect(BiconditionalExtractor.nameLooksLikeBiconditionalFlag("isActive"))
        #expect(BiconditionalExtractor.nameLooksLikeBiconditionalFlag("isFetchingData"))
        #expect(BiconditionalExtractor.nameLooksLikeBiconditionalFlag("isRefreshing"))
        #expect(!BiconditionalExtractor.nameLooksLikeBiconditionalFlag("isEnabled"))
        #expect(!BiconditionalExtractor.nameLooksLikeBiconditionalFlag("loading")) // case-sensitive
    }
}
