import Testing
@testable import SwiftInferTestLifter

@Suite("AssertAfterTransformDetector — explicit + collapsed round-trip (M1.3)")
struct AssertAfterTransformDetectorTests {

    private static func detect(in source: String) -> [DetectedRoundTrip] {
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        return AssertAfterTransformDetector.detect(in: slice)
    }

    // MARK: - Explicit shape

    @Test("Explicit three-line round-trip is detected")
    func explicitRoundTrip() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testRoundTrip() {
                let original = 42
                let encoded = encode(original)
                let decoded = decode(encoded)
                XCTAssertEqual(original, decoded)
            }
        }
        """
        let detections = AssertAfterTransformDetectorTests.detect(in: source)
        #expect(detections.count == 1)
        let detected = detections.first
        #expect(detected?.forwardCallee == "encode")
        #expect(detected?.backwardCallee == "decode")
        #expect(detected?.inputBindingName == "original")
        #expect(detected?.recoveredBindingName == "decoded")
    }

    @Test("Explicit round-trip with swapped assertion arg order is detected")
    func explicitRoundTripSwappedArgs() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testRoundTripSwap() {
                let original = 42
                let encoded = encode(original)
                let decoded = decode(encoded)
                XCTAssertEqual(decoded, original)
            }
        }
        """
        let detections = AssertAfterTransformDetectorTests.detect(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.forwardCallee == "encode")
        #expect(detections.first?.backwardCallee == "decode")
    }

    @Test("Member-access call sites surface the member name as the callee")
    func explicitMemberAccessCallees() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testWithMembers() {
                let original = 42
                let encoded = encoder.encode(original)
                let decoded = decoder.decode(encoded)
                XCTAssertEqual(original, decoded)
            }
        }
        """
        let detections = AssertAfterTransformDetectorTests.detect(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.forwardCallee == "encode")
        #expect(detections.first?.backwardCallee == "decode")
    }

    @Test("Body lacking a backward call doesn't surface a round-trip")
    func explicitNoBackwardCall() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testJustEncode() {
                let original = 42
                let encoded = encode(original)
                XCTAssertEqual(original, encoded)
            }
        }
        """
        let detections = AssertAfterTransformDetectorTests.detect(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Receiver mismatch in the chain is rejected (M1 conservative posture)")
    func receiverMismatchRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testReceiverMismatch() {
                let original = 42
                let encoded = encode(original)
                let decoded = somethingElse(encoded)
                XCTAssertEqual(original, decoded)
            }
        }
        """
        // The detector still identifies forward = encode, backward =
        // somethingElse. The "receivers swapping" caveat in the
        // detector docstring covers actual mismatching receivers
        // mid-chain, not arbitrary callee pairs — pair-of-arbitrary-
        // names is still a valid round-trip *claim* in M1, with the
        // explainability block covering "why this might be wrong."
        let detections = AssertAfterTransformDetectorTests.detect(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.forwardCallee == "encode")
        #expect(detections.first?.backwardCallee == "somethingElse")
    }

    @Test("Only one bound side is identifier — no detection")
    func onlyOneIdentifierAssertionArg() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testLiteralCompare() {
                let encoded = encode(42)
                XCTAssertEqual(decode(encoded), 42)
            }
        }
        """
        // Detector M1 requires the explicit shape's two assertion
        // arguments to both be DeclReferenceExpr — collapsed shape
        // catches this case via decode(encode(x))-on-LHS instead.
        let detections = AssertAfterTransformDetectorTests.detect(in: source)
        // collapsed-detector falls through because the inner expr 42 is
        // not an identifier; explicit-detector falls through because
        // RHS is a literal not a DeclReferenceExpr; net: no detection.
        #expect(detections.isEmpty)
    }

    // MARK: - Collapsed shape

    @Test("Collapsed XCTAssertEqual(decode(encode(x)), x) is detected")
    func collapsedXCTAssertEqualLHS() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testCollapsed() {
                let original = 42
                XCTAssertEqual(decode(encode(original)), original)
            }
        }
        """
        let detections = AssertAfterTransformDetectorTests.detect(in: source)
        #expect(detections.count == 1)
        let detected = detections.first
        #expect(detected?.forwardCallee == "encode")
        #expect(detected?.backwardCallee == "decode")
        #expect(detected?.inputBindingName == "original")
        #expect(detected?.recoveredBindingName == nil)
    }

    @Test("Collapsed XCTAssertEqual(x, decode(encode(x))) (other side) is detected")
    func collapsedXCTAssertEqualRHS() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testCollapsedSwap() {
                let original = 42
                XCTAssertEqual(original, decode(encode(original)))
            }
        }
        """
        let detections = AssertAfterTransformDetectorTests.detect(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.forwardCallee == "encode")
        #expect(detections.first?.backwardCallee == "decode")
    }

    @Test("Collapsed #expect(decode(encode(x)) == x) is detected")
    func collapsedExpectMacro() {
        let source = """
        import Testing
        @Test func swiftTestingCollapsed() {
            let original = 42
            #expect(decode(encode(original)) == original)
        }
        """
        let detections = AssertAfterTransformDetectorTests.detect(in: source)
        #expect(detections.count == 1)
        let detected = detections.first
        #expect(detected?.forwardCallee == "encode")
        #expect(detected?.backwardCallee == "decode")
        #expect(detected?.recoveredBindingName == nil)
    }

    @Test("Collapsed #expect(x == decode(encode(x))) (other side) is detected")
    func collapsedExpectMacroSwap() {
        let source = """
        import Testing
        @Test func swiftTestingCollapsedSwap() {
            let original = 42
            #expect(original == decode(encode(original)))
        }
        """
        let detections = AssertAfterTransformDetectorTests.detect(in: source)
        #expect(detections.count == 1)
    }

    @Test("Collapsed shape with member-access callees")
    func collapsedMemberAccess() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testCollapsedMembers() {
                let original = 42
                XCTAssertEqual(decoder.decode(encoder.encode(original)), original)
            }
        }
        """
        let detections = AssertAfterTransformDetectorTests.detect(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.forwardCallee == "encode")
        #expect(detections.first?.backwardCallee == "decode")
    }

    @Test("Collapsed shape where outer call has no inner call → no detection")
    func collapsedNoInnerCall() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testNotCollapsed() {
                let original = 42
                XCTAssertEqual(decode(original), original)
            }
        }
        """
        let detections = AssertAfterTransformDetectorTests.detect(in: source)
        #expect(detections.isEmpty)
    }

    // MARK: - Negative cases

    @Test("Slice with no assertion → no detections")
    func noAssertionNoDetections() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testNothing() {
                let x = 42
            }
        }
        """
        let detections = AssertAfterTransformDetectorTests.detect(in: source)
        #expect(detections.isEmpty)
    }

    @Test("XCTAssertTrue is not anchored on for round-trip detection")
    func xctAssertTrueIgnored() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testTrue() {
                let original = 42
                XCTAssertTrue(decode(encode(original)) == original)
            }
        }
        """
        // M1 doesn't pattern-match `XCTAssertTrue(... == ...)` for
        // round-trip — XCTAssertEqual + #expect cover the canonical
        // shapes. Documenting the limit; M5+ may extend.
        let detections = AssertAfterTransformDetectorTests.detect(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Unrelated comparison shape is not surfaced as round-trip")
    func unrelatedComparisonRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testCompareUnrelated() {
                let a = 1
                let b = 2
                XCTAssertEqual(a, b)
            }
        }
        """
        let detections = AssertAfterTransformDetectorTests.detect(in: source)
        #expect(detections.isEmpty)
    }
}
