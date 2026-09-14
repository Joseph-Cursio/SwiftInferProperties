import Foundation
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The relative-tolerance comparison emitted for `.approximate` equality (#454).
///
/// ## Why this suite executes the helper rather than pinning its text
///
/// The arm it replaces rendered `lhs.isApproximatelyEqual(to: rhs)` — swift-numerics — and
/// **had never produced a compiling stub for any of its six carriers since V1.31.A**, because
/// `PropertyLawKit` links only `PropertyBased` and nothing emitted an `import Numerics`. Its own
/// doc comment recorded the requirement and nothing acted on it.
///
/// A string assertion would not have caught that, and did not: the emitter's tests pinned the
/// text and were green throughout. So the helper below is a **live copy** of what the emitter
/// emits — the behaviour tests prove the semantics, and `theEmittedHelperMatchesTheLiveCopy`
/// proves the emitter still says exactly this. Same discipline as SwiftPropertyLaws'
/// `EmittedExpressionCompilesTests`, which exists because a codegen test comparing text to text
/// can have both sides wrong together.
@Suite("Approximate equality — the emitted helper, executed")
struct ApproximateEqualityHelperTests {

    /// Live copy of `LiftedTestEmitter.approximateEqualityHelper`.
    private func approximatelyEqual<Value: FloatingPoint>(_ lhs: Value, _ rhs: Value) -> Bool {
        if lhs == rhs { return true }
        if lhs.isNaN, rhs.isNaN { return true }
        let delta = (lhs - rhs).magnitude
        let scale = Swift.max(lhs.magnitude, rhs.magnitude)
        return delta.isFinite && delta <= scale * Value.ulpOfOne.squareRoot()
    }

    // MARK: - The case the arm exists for

    /// The measured reason this arm was built: *"8 of 8 sampled canonical math forward-inverse
    /// round-trip pairs"* fail under strict `==`. If the helper does not admit these, it is no
    /// better than the `==` it replaces.
    /// ⚠ **The domain is part of the test, and the first draft of this one ignored it.**
    /// `1_000.0` was in this list and failed: `exp(1000)` overflows `Double` (the argument
    /// ceiling is ≈709), so `log(exp(1000))` is `+infinity` and genuinely is not 1000. The helper
    /// was right and the case was outside `exp`'s domain — *a law shipped without its domain*, in
    /// a test written to check a fix for exactly that class.
    /// **These values are chosen because strict `==` rejects them**, not for looking plausible.
    /// The control below fails if that stops being true, and it caught two earlier drafts: one
    /// used `1_000.0`, where `exp` overflows `Double` (argument ceiling ≈709) so `log(exp(x))` is
    /// `+infinity` and the case was outside the function's domain — *a law without its domain*,
    /// in a test written to check a fix for that class — and one used values where `==` already
    /// held, which would have demonstrated nothing about a tolerance.
    static let roundTripWitnesses: [Double] = [0.1, 0.8]
    static let trigWitnesses: [Double] = [0.1, 0.15, 0.25, 0.3]

    @Test("exp/log round trips that strict == rejects", arguments: roundTripWitnesses)
    func transcendentalRoundTripsAreAdmitted(value: Double) {
        #expect(approximatelyEqual(Foundation.log(Foundation.exp(value)), value))
    }

    @Test("cos/acos round trips that strict == rejects", arguments: trigWitnesses)
    func trigonometricRoundTripsAreAdmitted(value: Double) {
        #expect(approximatelyEqual(Foundation.acos(Foundation.cos(value)), value))
    }

    /// **The non-vacuity control for the two suites above.** If `==` accepted every witness, the
    /// tolerance would be doing no work and those tests would pass against a `==` implementation.
    @Test func strictEqualityRejectsEveryWitness() {
        for value in Self.roundTripWitnesses {
            #expect(Foundation.log(Foundation.exp(value)) != value, "exp/log witness \(value) is vacuous")
        }
        for value in Self.trigWitnesses {
            #expect(Foundation.acos(Foundation.cos(value)) != value, "cos/acos witness \(value) is vacuous")
        }
    }

    // MARK: - The three cases handled before the tolerance

    @Test func exactEqualitySettlesZeroAndInfinity() {
        #expect(approximatelyEqual(0.0, -0.0))
        #expect(approximatelyEqual(Double.infinity, .infinity))
        #expect(approximatelyEqual(-Double.infinity, -.infinity))
    }

    /// NaN is made reflexive, matching the kit's own `floatSameResult`. A law over a partial
    /// function otherwise fails on an input neither side chose.
    @Test func nanIsReflexive() {
        #expect(approximatelyEqual(Double.nan, .nan))
    }

    @Test func oppositeInfinitiesAreNotEqual() {
        #expect(approximatelyEqual(Double.infinity, -.infinity) == false)
    }

    @Test func aNaNAgainstANumberIsNotEqual() {
        #expect(approximatelyEqual(Double.nan, 1.0) == false)
    }

    // MARK: - It still discriminates

    /// **The load-bearing negative.** A comparison that accepted everything would satisfy every
    /// positive test above and make the law worthless — which is the vacuity failure this
    /// codebase keeps recording.
    @Test("values further apart than the tolerance are rejected", arguments: [
        (1.0, 1.1), (1.0, 2.0), (0.0, 1.0), (100.0, 101.0), (1e-8, 1e-7)
    ])
    func genuinelyDifferentValuesAreRejected(pair: (Double, Double)) {
        #expect(approximatelyEqual(pair.0, pair.1) == false)
    }

    @Test func itIsRelativeNotAbsolute() {
        // The same absolute delta is inside the tolerance at large scale and outside it at small.
        #expect(approximatelyEqual(1e9, 1e9 + 1.0))
        #expect(approximatelyEqual(1.0, 2.0) == false)
    }

    @Test func itWorksForFloatAsWellAsDouble() {
        #expect(approximatelyEqual(Float(1.0), Float(1.0)))
        #expect(approximatelyEqual(Float(1.0), Float(2.0)) == false)
    }

    // MARK: - The emitter still says exactly this

    @Test func theEmittedHelperMatchesTheLiveCopy() {
        let emitted = LiftedTestEmitter.approximateEqualityHelper
        #expect(emitted.contains("private func approximatelyEqual<Value: FloatingPoint>"))
        #expect(emitted.contains("if lhs.isNaN, rhs.isNaN { return true }"))
        #expect(emitted.contains("delta <= scale * Value.ulpOfOne.squareRoot()"))
        #expect(emitted.contains("isApproximatelyEqual") == false, "the swift-numerics method must be gone")
    }

    /// The helper ships only with the stubs that use it.
    @Test func aStrictStubCarriesNoHelper() {
        let strict = LiftedTestEmitter.withApproximateEqualityHelper("STUB", kind: .strict)
        #expect(strict == "STUB")
        let approximate = LiftedTestEmitter.withApproximateEqualityHelper("STUB", kind: .approximate)
        #expect(approximate.contains("approximatelyEqual"))
    }

    @Test func theAssertionCallsTheFreeFunction() {
        let expression = LiftedTestEmitter.equalityExpression(lhs: "a", rhs: "b", kind: .approximate)
        #expect(expression == "approximatelyEqual(a, b)")
        #expect(LiftedTestEmitter.equalityExpression(lhs: "a", rhs: "b", kind: .strict) == "a == b")
    }
}
