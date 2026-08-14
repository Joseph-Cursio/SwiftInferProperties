@testable import SwiftInferTestLifter
import Testing

/// Guards the two widenings made 2026-08-14 so the round-trip detector reads the way a human
/// writes a round-trip test.
///
/// Measured: `SwiftFormatConfigTests.roundTrip` states the top-scoring suggestion's law
/// byte-exactly and contributed **zero** cross-validation signals across 19 picks
/// (`docs/measurements/exploratory-swiftformatrulestudio.md` §5.2). Two independent causes,
/// either alone enough to hide it:
///
/// 1. the value reaches the second call through the **receiver** (`parse(x).serialized()`),
///    where the detector read `arguments.first`;
/// 2. the input is `Self.sample`, a **member access**, where the detector required a
///    `DeclReferenceExprSyntax` on both sides.
///
/// **The rejection arms carry the precision** — see `callExpressionInputIsRejected`, which is
/// the reason the second widening compares only *value references* and not arbitrary text.
@Suite("Round-trip detector — the spellings a human writes")
struct RoundTripSpellingTests {

    private static func detect(in source: String) -> [DetectedRoundTrip] {
        AssertAfterTransformDetector.detect(in: SlicerTestHelper.sliceFirstBody(in: source))
    }

    private static func swiftTestingCase(_ assertion: String, preamble: String = "") -> String {
        """
        import Testing
        @Suite("S") struct S {
            static let sample = "--indent 4"
            @Test("t") func roundTrip() {
                \(preamble)
                #expect(\(assertion))
            }
        }
        """
    }

    // MARK: - Receiver position

    @Test("the method-chain spelling is detected — value through the RECEIVER")
    func receiverPositionDetected() {
        // `Cfg.parse(x).serialized()` — the outer call takes no arguments at all, so the old
        // `arguments.first` read returned nil and the whole shape failed.
        let detections = Self.detect(
            in: Self.swiftTestingCase("Cfg.parse(sample).serialized() == sample", preamble: "let sample = \"a\"")
        )
        #expect(detections.count == 1)
        #expect(detections.first?.forwardCallee == "parse")
        #expect(detections.first?.backwardCallee == "serialized")
    }

    @Test("the nested-call spelling still works — the shape that always did")
    func argumentPositionStillDetected() {
        // The control. Receiver support must not cost the form the detector was built for.
        let detections = Self.detect(
            in: Self.swiftTestingCase("decode(encode(sample)) == sample", preamble: "let sample = \"a\"")
        )
        #expect(detections.count == 1)
        #expect(detections.first?.forwardCallee == "encode")
        #expect(detections.first?.backwardCallee == "decode")
    }

    // MARK: - Input spelling

    @Test("a static-member input is detected — the measured witness")
    func staticMemberInputDetected() {
        // Exactly `SwiftFormatConfigTests.roundTrip`.
        let detections = Self.detect(
            in: Self.swiftTestingCase("Cfg.parse(Self.sample).serialized() == Self.sample")
        )
        #expect(detections.count == 1)
        #expect(detections.first?.inputBindingName == "Self.sample")
    }

    @Test("a literal input is detected")
    func literalInputDetected() {
        let detections = Self.detect(
            in: Self.swiftTestingCase("Cfg.parse(\"--indent 4\").serialized() == \"--indent 4\"")
        )
        #expect(detections.count == 1)
    }

    @Test("two DIFFERENT references are not a round-trip")
    func mismatchedReferencesRejected() {
        // The sides must denote the same value. Widening the comparison from `baseName` to
        // text must not weaken that.
        #expect(Self.detect(
            in: Self.swiftTestingCase("Cfg.parse(Self.sample).serialized() == Self.other")
        ).isEmpty)
    }

    // MARK: - The precision arm

    @Test("a CALL as the input is rejected, however matching the text")
    func callExpressionInputIsRejected() {
        // `f(makeValue()).g() == makeValue()` states a law only if `makeValue` is
        // deterministic. Comparing raw expression text would match it and report the codebase
        // as corroborating a law it never asserted — so a call is not a value reference. This
        // is the arm that makes the text comparison safe; delete it and the widening becomes
        // "any two identical-looking expressions".
        #expect(Self.detect(
            in: Self.swiftTestingCase("Cfg.parse(makeValue()).serialized() == makeValue()")
        ).isEmpty)
    }

    @Test("a member access ROOTED IN a call is rejected")
    func computedMemberBaseRejected() {
        // `loader().text` reads a property off a fresh computation; the base chain must be all
        // references for the expression to denote a stable value.
        #expect(Self.detect(
            in: Self.swiftTestingCase("Cfg.parse(loader().text).serialized() == loader().text")
        ).isEmpty)
    }

    @Test("a deep but pure member chain is accepted")
    func pureMemberChainAccepted() {
        #expect(Self.detect(
            in: Self.swiftTestingCase("Cfg.parse(Fixtures.config.text).serialized() == Fixtures.config.text")
        ).count == 1)
    }
}
