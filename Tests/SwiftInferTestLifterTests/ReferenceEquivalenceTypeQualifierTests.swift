@testable import SwiftInferTestLifter
import Testing

/// A type qualifier is not a shared input (issue #241).
///
/// `AssertReferenceEquivalenceDetector` fires when both sides of an equality are calls,
/// the callees differ, and some identifier appears on both — that shared identifier being
/// what makes the assertion a comparison of two computations over ONE value rather than
/// two unrelated values that happen to be equal.
///
/// The receiver of a call counted toward that set, so `Self.f(x)` contributed `Self`. Two
/// static helpers on one type therefore always "shared an input", and the gate was open
/// for any pair of them. Measured on a real suite: `Self.normalized(source) == source`,
/// where `source` binds to `Self.lossless(seed:)`, lifted as
/// `normalized(x) == lossless(x)` at **Strong** — the top tier — for a law that cannot be
/// written, since `normalized` takes a `String` and `lossless` a `UInt64`. The assertion
/// is a fixed point and the "reference" was the generator that produced its input.
///
/// Split from `AssertReferenceEquivalenceDetectorTests` because these pushed that type
/// past the 250-line body cap, not because they are a separate concern.
@Suite("Reference equivalence — type qualifiers are not inputs")
struct ReferenceEquivalenceTypeQualifierTests {

    private static func detect(in source: String) -> [DetectedReferenceEquivalence] {
        AssertReferenceEquivalenceDetector.detect(in: SlicerTestHelper.sliceFirstBody(in: source))
    }

    @Test("two static helpers on one type do not pair on `Self`")
    func staticHelpersDoNotPairOnSelf() {
        // Measured on a real suite. `source` binds to `Self.lossless(seed:)`, so after
        // binding resolution BOTH sides are calls with different callees — and the only
        // identifier they shared was `Self`, the namespace. That was enough to fire this
        // detector, and the lifted law reached **Strong**.
        //
        // The law it proposed cannot be written: `normalized` takes a `String` and
        // `lossless` takes a `UInt64`, so no argument satisfies both. The assertion is a
        // FIXED POINT — `normalized(x) == x` — and the "reference" is the generator that
        // produced x.
        #expect(Self.detect(in: """
        import Testing
        struct T {
            @Test func exactRoundTripHoldsOnTheLosslessDomain() {
                for seed in UInt64(1)...500 {
                    let source = Self.lossless(seed: seed)
                    #expect(Self.normalized(source) == source)
                }
            }
        }
        """).isEmpty)
    }

    @Test("nor on a named type qualifier")
    func staticHelpersDoNotPairOnATypeName() {
        // The same defect wearing the type's real name rather than `Self`, which is how it
        // would present in a test that spells the enclosing type out.
        //
        // `seed` is bound rather than written `build(seed: 7)`, and that detail is the
        // difference between a test and a decoration: with the literal inline, the
        // pre-existing `hasLiteralArgument` guard rejects the pair before reaching the
        // type-qualifier check, so the arm passed identically with the fix reverted.
        // Caught by mutating the guard — the version with the literal could not fail.
        #expect(Self.detect(in: """
        import Testing
        struct T {
            @Test func check() {
                let seed = makeSeed()
                let text = Fixtures.build(seed: seed)
                #expect(Fixtures.normalize(text) == text)
            }
        }
        """).isEmpty)
    }

    @Test("a lowercase receiver is still an input — the exclusion is narrow")
    func valueReceiverStillPairs() throws {
        // The control. `isTypeQualifier` keys on Swift's UpperCamelCase convention, so a
        // VALUE receiver keeps its receiver-as-input route: without this arm the fix could
        // have disabled the detector's canonical shape and every test above would still
        // pass, since none of them reaches it through a qualified static call.
        let detections = Self.detect(in: """
        import Testing
        struct T {
            @Test func check() {
                let input = [3, 1, 2]
                #expect(mySort(input) == input.sorted())
            }
        }
        """)
        let detection = try #require(detections.first)
        #expect(detection.subjectCallee == "mySort")
        #expect(detection.sharedInput == "input")
    }

    @Test("a statically-qualified oracle still pairs through its ARGUMENT")
    func staticOracleStillPairsOnTheArgument() throws {
        // What the fix must NOT cost. A reference implementation reached through a type
        // (`Reference.sort(x)`) is a genuine oracle; it pairs on `x` because both sides
        // take it as an argument. Only the receiver route narrowed.
        let detections = Self.detect(in: """
        import Testing
        struct T {
            @Test func check() {
                let input = [3, 1, 2]
                #expect(mySort(input) == Reference.sort(input))
            }
        }
        """)
        let detection = try #require(detections.first)
        #expect(detection.sharedInput == "input")
    }
}
