import Foundation
@testable import SwiftInferTemplates
import SwiftParser
import SwiftSyntax
import Testing

// V1.94 (cycle-91) — tests for the @Presents / @PresentationState
// attribute-recognition extension to CardinalityWitnessDetector.
// Sibling to CardinalityWitnessDetectorTests (the original M5
// suite) — separates concerns + keeps both files under SwiftLint's
// type-body length cap. Modern TCA's `@Presents var destination:
// Destination.State?` pattern was invisible to the v1.93 detector
// because property names like `destination` / `counter` failed
// the curated name-pattern check.

@Suite("CardinalityWitnessDetector — V1.94 @Presents attribute path")
struct CardinalityPresentsAttributeTests {

    @Test("V1.94 — two @Presents Optionals fire witness regardless of name")
    func twoPresentsAttributedOptionalsFire() {
        // The canonical modern-TCA pattern. `destination` and
        // `counter` would fail the name-pattern check (no "sheet" /
        // "alert" substring) without the attribute path. Cycle-3
        // measurement showed every TCA 1.25.5 `@Presents var
        // destination: ...` missed for exactly this reason.
        let source = """
        struct AppState {
            @Presents var destination: Destination.State?
            @Presents var counter: Counter.State?
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
    }

    @Test("V1.94 — @PresentationState alias is also recognized")
    func presentationStateAliasFires() {
        // Older TCA used `@PresentationState`; modern (1.7+) aliases
        // it to `@Presents`. The detector accepts both names.
        let source = """
        struct AppState {
            @PresentationState var destination: Destination.State?
            @PresentationState var counter: Counter.State?
        }
        """
        let witnesses = CardinalityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
        #expect(witnesses[0].fields.count == 2)
    }

    @Test("V1.94 — mixing @Presents Optional with isShowing Bool fires witness")
    func presentsMixedWithBoolFires() {
        let source = """
        struct AppState {
            @Presents var destination: Destination.State?
            var isShowingMenu: Bool
        }
        """
        let witnesses = CardinalityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
        let fields = witnesses[0].fields
        #expect(fields.count == 2)
        #expect(fields.contains { $0.kind == .optionalPresentation })
        #expect(fields.contains { $0.kind == .boolFlag })
    }

    @Test("V1.94 — single @Presents Optional alone produces no witness")
    func singlePresentsDoesNotFire() {
        // Cardinality requires ≥ 2 fields. One @Presents Optional on
        // its own can't form a mutually-exclusive set.
        let source = """
        struct AppState {
            @Presents var destination: Destination.State?
            var unrelatedString: String
        }
        """
        let witnesses = CardinalityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.isEmpty)
    }

    @Test("V1.94 — @Presents on a non-Optional field is skipped")
    func presentsOnNonOptionalSkipped() {
        // The attribute alone isn't sufficient — the field must also
        // be Optional. A non-Optional `@Presents` would be a
        // user error TCA itself would reject; skipped quietly to
        // avoid producing a witness that doesn't match the
        // detector's "Optional is nil-or-not" semantics.
        let source = """
        struct AppState {
            @Presents var brokenNonOptional: Int
            @Presents var destination: Destination.State?
        }
        """
        let witnesses = CardinalityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        // Only the destination qualifies; need ≥ 2 → no witness.
        #expect(witnesses.isEmpty)
    }

    @Test("V1.94 — only @Presents / @PresentationState relax the name-pattern check")
    func otherAttributesDoNotRelaxNameCheck() {
        // Exercise the helper indirectly via classifyBinding — true
        // for an Optional with @Presents, false with @MainActor.
        // Captures the attribute-name match precisely (not just
        // "any attribute").
        let withPresents = """
        struct AppState {
            @Presents var alpha: Beta?
            @Presents var gamma: Delta?
        }
        """
        let withMainActor = """
        struct AppState {
            @MainActor var alpha: Beta?
            @MainActor var gamma: Delta?
        }
        """
        #expect(
            CardinalityWitnessDetector.detect(stateTypeName: "AppState", in: withPresents).count == 1
        )
        // @MainActor doesn't relax the name-pattern check; both
        // `alpha` / `gamma` are non-pattern-matching names.
        #expect(
            CardinalityWitnessDetector.detect(stateTypeName: "AppState", in: withMainActor).isEmpty
        )
    }
}
