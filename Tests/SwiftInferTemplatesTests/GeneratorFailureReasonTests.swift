import Foundation
@testable import SwiftInferTemplates
import Testing

/// The `.todo` generator marker names WHY nothing derived, instead of saying the same fixed
/// sentence for every cause.
///
/// **`GeneratorResolver` has answered this since kit v4.7.0 and this repository discarded the
/// answer.** `resolutionFailure(forTypeName:)` returns one case per `nil` path — `.notInUniverse`,
/// `.ambiguous`, `.aliasUnresolved`, `.noStrategy(reason:)` carrying the strategist's own
/// sentence verbatim, `.unterminatedRecursion` — and every emitted stub rendered the same string
/// regardless. Measured on the 2026-09-19 corpus run: **656 markers, all identical**, so five
/// different problems were indistinguishable to a reader and to a census.
///
/// The kit's own commit measured the cost downstream, in this repository: the missing-generator
/// census *"had to reconstruct two of the `nil` paths and guess the third, and left 370 of 2,016
/// unresolved types (18.4%) unexplained for that reason alone"*.
@Suite("The .todo generator marker names its cause")
struct GeneratorFailureReasonTests {

    @Test("a reason is spliced into the marker")
    func reasonAppears() {
        let marker = LiftedTestEmitter.todoGeneratorMarker(reason: "`Foo` is not among the scanned types")
        #expect(marker.contains("not among the scanned types"))
        #expect(marker.contains("supply `static func gen()`"))
    }

    /// The old behaviour, kept for every caller that holds no resolver.
    @Test("no reason falls back to the sentence every stub used to carry")
    func withoutAReason() {
        #expect(LiftedTestEmitter.todoGeneratorMarker(reason: nil)
            == LiftedTestEmitter.todoGeneratorMarker)
        #expect(!LiftedTestEmitter.todoGeneratorMarker.contains("—  ;"))
    }

    @Test("an empty reason is treated as no reason, not as an empty clause")
    func emptyReason() {
        #expect(LiftedTestEmitter.todoGeneratorMarker(reason: "")
            == LiftedTestEmitter.todoGeneratorMarker)
    }

    /// ⚠ **The marker is spliced INTO an expression**, so anything that closes the block comment
    /// early breaks the stub in a way that has nothing to do with the missing generator — which
    /// is the failure the marker exists to report clearly. A reason is not trusted to be
    /// comment-safe just because the kit writes it today.
    @Test("a reason cannot close the block comment early")
    func reasonCannotEscapeTheComment() {
        let marker = LiftedTestEmitter.todoGeneratorMarker(reason: "ends here */ and then code()")
        // Everything between the opening `/*` and the final `*/` must contain no `*/` of its
        // own, or the comment closed early and the rest of the expression became code.
        let interior = marker
            .replacingOccurrences(of: " /* ", with: "")
            .replacingOccurrences(of: " */", with: "")
        #expect(!interior.contains("*/"), "the reason closed the comment early")
        #expect(marker.hasSuffix("*/"))
    }

    @Test("a multi-line reason is folded onto one line")
    func reasonIsFolded() {
        let marker = LiftedTestEmitter.todoGeneratorMarker(reason: "first line\nsecond line")
        #expect(!marker.contains("\n"))
        #expect(marker.contains("first line second line"))
    }

    /// The control: a type the kit CAN generate must not acquire a marker just because a reason
    /// was offered. `defaultGenerator` answers from `RawType` long before the `.todo` arm.
    @Test("a resolvable type is unaffected by a reason being available")
    func resolvableTypeIsUnchanged() {
        let withReason = LiftedTestEmitter.defaultGenerator(for: "Int", reason: "ignored")
        let without = LiftedTestEmitter.defaultGenerator(for: "Int")
        #expect(withReason == without)
        #expect(!withReason.contains("no generator derived"))
    }

    @Test("an unresolvable type carries the reason it was given")
    func unresolvableTypeCarriesIt() {
        let generated = LiftedTestEmitter.defaultGenerator(
            for: "SomeProjectType", reason: "memberwise derivation supports structs only"
        )
        #expect(generated.contains("SomeProjectType.gen()"))
        #expect(generated.contains("memberwise derivation supports structs only"))
    }
}
