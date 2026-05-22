import Foundation
import Testing
@testable import SwiftInferTemplates

// V1.97 (cycle-94) — tests for the inferred-Bool-from-literal-initializer
// extension to BiconditionalWitnessDetector. Sibling to the M7 suite
// to keep both files under SwiftLint's type-body length cap.
//
// The cycle-93 detector required an explicit `: Bool` annotation on
// the Bool half of the biconditional pair. Modern TCA's idiomatic
// State shape is `var isLoading = false` (no annotation; relies on
// type inference). Cycle-93 measurement showed biconditional at 0
// across all of TCA 1.25.5 / 1.0.0 — `04-NavigationStack.swift`'s
// `(fact: String?, isLoading: <inferred Bool>)` is exactly the pair
// the M7 detector is after, but the typeAnnotation-required gate
// missed it.

@Suite("BiconditionalWitnessDetector — V1.97 inferred-Bool initializer path")
struct BiconditionalInferredBoolTests {

    @Test("V1.97 — inferred Bool from `= false` initializer fires biconditional pair")
    func inferredBoolPairsWithOptional() {
        // The real-world TCA shape, copied from
        // `04-NavigationStack.swift`.
        let source = """
        struct State {
            var fact: String?
            var isLoading = false
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "State",
            in: source
        )
        #expect(witnesses.count == 1)
        #expect(witnesses[0].boolPropertyName == "isLoading")
        #expect(witnesses[0].boolTypeName == "Bool")
        #expect(witnesses[0].optionalPropertyName == "fact")
    }

    @Test("V1.97 — inferred Bool from `= true` initializer also matches")
    func inferredBoolTrueInitializer() {
        let source = """
        struct State {
            var maybeFact: String?
            var isActive = true
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "State",
            in: source
        )
        #expect(witnesses.count == 1)
        #expect(witnesses[0].boolPropertyName == "isActive")
    }

    @Test("V1.97 — string-literal initializer does NOT trigger Bool inference")
    func stringLiteralDoesNotTriggerBoolInference() {
        // Defensive — only `BooleanLiteralExprSyntax` should
        // count. `var isLoading = "false"` is a String,
        // structurally distinct.
        let source = """
        struct State {
            var fact: String?
            var isLoading = "false"
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "State",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("V1.97 — Int-literal initializer doesn't trigger Bool inference")
    func intLiteralDoesNotTriggerBoolInference() {
        let source = """
        struct State {
            var fact: String?
            var isLoading = 0
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "State",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("V1.97 — inferred Bool without name-pattern match doesn't fire")
    func inferredBoolNonMatchingNameRejected() {
        // The inferred-Bool path still goes through
        // nameLooksLikeBiconditionalFlag — only `is*` patterns
        // matching the curated list (Loading/Showing/Presenting/
        // Active/Fetching/Refreshing) qualify. `isEnabled` is
        // outside that set.
        let source = """
        struct State {
            var fact: String?
            var isEnabled = false
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "State",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("V1.97 — explicit `: Bool` annotation still works (regression guard)")
    func explicitBoolAnnotationStillWorks() {
        // The annotation-bearing path is unchanged; this confirms
        // we didn't accidentally regress the existing detector
        // behavior while adding the inferred-Bool branch.
        let source = """
        struct State {
            var fact: String?
            var isLoading: Bool = false
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "State",
            in: source
        )
        #expect(witnesses.count == 1)
        #expect(witnesses[0].boolPropertyName == "isLoading")
    }

    @Test("V1.97 — mixed inferred + explicit Bools all surface via Cartesian product")
    func mixedInferredAndExplicitBools() {
        // Realistic TCA shape: some Bools annotated, others
        // inferred, all paired against a single Optional.
        let source = """
        struct State {
            var fact: String?
            var isLoading = false
            var isShowing: Bool = false
        }
        """
        let witnesses = BiconditionalWitnessDetector.detect(
            stateTypeName: "State",
            in: source
        )
        #expect(witnesses.count == 2)
        let boolNames = Set(witnesses.map(\.boolPropertyName))
        #expect(boolNames == ["isLoading", "isShowing"])
    }
}
