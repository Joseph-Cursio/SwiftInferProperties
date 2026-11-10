import Foundation
@testable import SwiftInferTemplates
import Testing

// V1.105 (cycle-102 Finding D fix) — regression tests for the
// cardinality-overlap suppression in BiconditionalExtractor.
// Pure: parse a source snippet, assert on detected witnesses.

@Suite("BiconditionalWitnessDetector — V1.105 cardinality-overlap suppression")
struct BicondPresentationOverlapTests {

    @Test func threeSlotPresentationOverlapSuppressed() {
        // The HandRolled Hand03 shape: two presentation Bools +
        // one presentation Optional. Cardinality fires once on
        // the 3-slot mutual-exclusion. Pre-fix, bicond also fired
        // 2 redundant pairings (isShowingSheet × cover,
        // isShowingAlert × cover) — both have predicates that
        // are unrelated to the actual presentation semantics.
        // Post-fix, both bicond pairings are suppressed because
        // each Bool + the cover Optional are all in a 3+-slot
        // cardinality presentation-field set.
        let source = """
        struct AppState {
            var isShowingSheet: Bool
            var isShowingAlert: Bool
            var activeFullScreenCover: String?
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test func twoSlotPresentationPairStillFires() {
        // The 2-slot case (`isShowingSheet` + `sheet: Sheet?`)
        // legitimately suggests both cardinality AND biconditional;
        // the triage rubric handles disambiguation. The filter is
        // narrow (only ≥ 3-slot cardinality witnesses suppress),
        // so 2-slot presentation pairs continue to fire bicond.
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
        #expect(witnesses[0].optionalPropertyName == "sheet")
    }

    @Test func nonPresentationBoolStillPairs() {
        // `isLoading` doesn't match the cardinality presentation
        // Bool patterns (Showing/Presenting). The pairing with
        // `fact: String?` (also non-presentation since `fact`
        // doesn't lowercase-contain sheet/alert/fullscreencover/
        // popover) survives.
        let source = """
        struct AppState {
            var isLoading: Bool
            var fact: String?
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
        #expect(witnesses[0].boolPropertyName == "isLoading")
        #expect(witnesses[0].optionalPropertyName == "fact")
    }

    @Test func presentationBoolWithNonPresentationOptionalSurvives() {
        // `isShowingSheet` is a presentation Bool, but `fact` is
        // not a presentation Optional. The pair is NOT both-
        // presentation, so it survives the filter. This guards
        // the narrow-scope intent of the suppression: only the
        // both-presentation overlap is suppressed.
        let source = """
        struct AppState {
            var isShowingSheet: Bool
            var fact: String?
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
        #expect(witnesses[0].boolPropertyName == "isShowingSheet")
        #expect(witnesses[0].optionalPropertyName == "fact")
    }

    @Test func nonPresentationBoolWithPresentationOptionalSurvives() {
        // Symmetric case: presentation Optional + non-presentation
        // Bool. The pair is also NOT both-presentation. Survives.
        let source = """
        struct AppState {
            var isLoading: Bool
            var activeSheet: SheetKind?
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
        #expect(witnesses[0].boolPropertyName == "isLoading")
        #expect(witnesses[0].optionalPropertyName == "activeSheet")
    }

    @Test func tcaNavigateAndLoadShapeUnaffected() {
        // The real-corpus TCA pattern: `isNavigationActive` ×
        // `optionalCounter`. `isNavigationActive` matches the
        // cardinality Bool pattern via `Active` substring? No
        // — cardinality only matches Showing/Presenting (not
        // Active). So this Bool is NOT a cardinality candidate,
        // and the pair survives.
        let source = """
        struct AppState {
            var isNavigationActive: Bool
            var optionalCounter: CounterState?
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
        #expect(witnesses[0].boolPropertyName == "isNavigationActive")
        #expect(witnesses[0].optionalPropertyName == "optionalCounter")
    }

    @Test func hand05LoadingResultsCachedResultStillPairs() {
        // The HandRolled Hand05 shape: `isLoadingResults` ×
        // `cachedResult` is a known noise case (semantically the
        // loading flag tracks the in-flight task, not the
        // persistent cache). But neither field is a cardinality
        // candidate (cachedResult doesn't match presentation
        // names), so the filter doesn't suppress it. The triage
        // rubric handles the semantic distinction.
        let source = """
        struct AppState {
            var isLoadingResults: Bool
            var activeTask: TaskHandle?
            var cachedResult: String?
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 2)
        let optionalNames = Set(witnesses.map(\.optionalPropertyName))
        #expect(optionalNames == ["activeTask", "cachedResult"])
    }
}
