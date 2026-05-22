import Foundation
import Testing
@testable import SwiftInferTemplates

// V2.0 M5 — CardinalityWitnessDetector tests. Pure: parse a
// source snippet, assert on detected witnesses.

@Suite("CardinalityWitnessDetector — V2.0 M5 presentation-field detection")
struct CardinalityWitnessDetectorTests {

    // MARK: - Detection happy path

    @Test("two Optional presentation fields → one witness with both")
    func twoOptionalsFireWitness() {
        let source = """
        struct AppState {
            var activeSheet: SheetKind?
            var activeAlert: AlertKind?
        }
        """
        let witnesses = CardinalityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
        let fields = witnesses[0].fields
        #expect(fields.count == 2)
        #expect(fields.allSatisfy { $0.kind == .optionalPresentation })
        #expect(fields.allSatisfy { $0.indicator.hasSuffix("!= nil") })
    }

    @Test("two Bool flag fields → one witness with both")
    func twoBoolsFireWitness() {
        let source = """
        struct AppState {
            var isShowingSheet: Bool
            var isPresentingDetail: Bool
        }
        """
        let witnesses = CardinalityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
        let fields = witnesses[0].fields
        #expect(fields.count == 2)
        #expect(fields.allSatisfy { $0.kind == .boolFlag })
        #expect(fields.allSatisfy { $0.indicator.hasPrefix("state.") })
        #expect(fields.allSatisfy { !$0.indicator.contains("!= nil") })
    }

    @Test("mixed Bool + Optional → witness contains both kinds")
    func mixedKinds() {
        let source = """
        struct Settings {
            struct State {
                var activeSheet: Sheet?
                var activeAlert: Alert?
                var isFullScreenPresenting: Bool
            }
        }
        """
        let witnesses = CardinalityWitnessDetector.detect(
            stateTypeName: "Settings.State",
            in: source
        )
        #expect(witnesses.count == 1)
        let fields = witnesses[0].fields
        #expect(fields.count == 3)
        let optionalCount = fields.filter { $0.kind == .optionalPresentation }.count
        let boolCount = fields.filter { $0.kind == .boolFlag }.count
        #expect(optionalCount == 2)
        #expect(boolCount == 1)
    }

    @Test("fullScreenCover / popover Optional names also match")
    func fullScreenCoverPopoverNames() {
        let source = """
        struct AppState {
            var fullScreenCover: Cover?
            var popover: Popover?
        }
        """
        let witnesses = CardinalityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
        #expect(witnesses[0].fields.count == 2)
    }

    // MARK: - Negatives

    @Test("only one presentation field → no witness (need ≥ 2)")
    func singleFieldNoWitness() {
        let source = """
        struct AppState {
            var activeSheet: SheetKind?
            var counter: Int
        }
        """
        let witnesses = CardinalityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("Bool field not matching the name pattern → not a flag")
    func unmatchedBoolName() {
        let source = """
        struct AppState {
            var isEnabled: Bool
            var isActive: Bool
        }
        """
        let witnesses = CardinalityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("Optional with non-presentation name → no match")
    func unmatchedOptionalName() {
        let source = """
        struct AppState {
            var selectedID: UUID?
            var draft: Item?
        }
        """
        let witnesses = CardinalityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("computed properties skipped (no invariant to verify)")
    func computedPropertiesSkipped() {
        let source = """
        struct AppState {
            var isShowingSheet: Bool { false }
            var isPresentingDetail: Bool { true }
        }
        """
        let witnesses = CardinalityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("static properties skipped")
    func staticPropertiesSkipped() {
        let source = """
        struct AppState {
            static var isShowingSheet: Bool = false
            static var isPresentingDetail: Bool = false
        }
        """
        let witnesses = CardinalityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("target type not found → empty result")
    func targetNotFound() {
        let source = """
        struct OtherState {
            var activeSheet: Sheet?
            var activeAlert: Alert?
        }
        """
        let witnesses = CardinalityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    // MARK: - Helper extractors

    @Test("isBoolType matches Bool / Swift.Bool")
    func isBoolType() {
        #expect(CardinalityFieldExtractor.isBoolType("Bool"))
        #expect(CardinalityFieldExtractor.isBoolType("Swift.Bool"))
        #expect(!CardinalityFieldExtractor.isBoolType("Bool?"))
        #expect(!CardinalityFieldExtractor.isBoolType("Int"))
    }

    @Test("isOptionalType matches T? and Optional<T>")
    func isOptionalType() {
        #expect(CardinalityFieldExtractor.isOptionalType("Sheet?"))
        #expect(CardinalityFieldExtractor.isOptionalType("Optional<Sheet>"))
        #expect(CardinalityFieldExtractor.isOptionalType("Swift.Optional<Sheet>"))
        #expect(!CardinalityFieldExtractor.isOptionalType("Bool"))
        #expect(!CardinalityFieldExtractor.isOptionalType("[Item]"))
    }

    @Test("matchesBoolPattern requires Showing / Presenting substring (case-sensitive — Swift camelCase)")
    func matchesBoolPattern() {
        #expect(CardinalityFieldExtractor.matchesBoolPattern("isShowingSheet"))
        #expect(CardinalityFieldExtractor.matchesBoolPattern("isPresentingDetail"))
        #expect(CardinalityFieldExtractor.matchesBoolPattern("isItemShowing"))
        // Case-sensitive — lowercase initial doesn't match Swift convention.
        #expect(!CardinalityFieldExtractor.matchesBoolPattern("showingPanel"))
        #expect(!CardinalityFieldExtractor.matchesBoolPattern("isEnabled"))
        #expect(!CardinalityFieldExtractor.matchesBoolPattern("isactive"))
    }

    @Test("matchesOptionalPattern is case-insensitive across the curated set")
    func matchesOptionalPattern() {
        #expect(CardinalityFieldExtractor.matchesOptionalPattern("activeSheet"))
        #expect(CardinalityFieldExtractor.matchesOptionalPattern("Alert"))
        #expect(CardinalityFieldExtractor.matchesOptionalPattern("fullScreenCover"))
        #expect(CardinalityFieldExtractor.matchesOptionalPattern("Popover"))
        #expect(CardinalityFieldExtractor.matchesOptionalPattern("PRESENTEDSHEET"))
        #expect(!CardinalityFieldExtractor.matchesOptionalPattern("selectedID"))
    }
}
