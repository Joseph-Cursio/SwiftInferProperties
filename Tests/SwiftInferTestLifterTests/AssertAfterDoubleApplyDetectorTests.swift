import Testing
@testable import SwiftInferTestLifter

@Suite("AssertAfterDoubleApplyDetector — explicit + collapsed idempotence (M2.1)")
struct AssertAfterDoubleApplyDetectorTests {

    private static func detect(in source: String) -> [DetectedIdempotence] {
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        return AssertAfterDoubleApplyDetector.detect(in: slice)
    }

    // MARK: - Explicit shape

    @Test("Explicit three-line idempotence is detected")
    func explicitIdempotence() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testNormalizeIsIdempotent() {
                let s = "hello"
                let once = normalize(s)
                let twice = normalize(once)
                XCTAssertEqual(once, twice)
            }
        }
        """
        let detections = AssertAfterDoubleApplyDetectorTests.detect(in: source)
        #expect(detections.count == 1)
        let detected = detections.first
        #expect(detected?.calleeName == "normalize")
        #expect(detected?.inputBindingName == "s")
    }

    @Test("Explicit idempotence with swapped assertion arg order is detected")
    func explicitIdempotenceSwappedArgs() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testIdempotentSwap() {
                let s = "hello"
                let once = normalize(s)
                let twice = normalize(once)
                XCTAssertEqual(twice, once)
            }
        }
        """
        let detections = AssertAfterDoubleApplyDetectorTests.detect(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.calleeName == "normalize")
    }

    @Test("Explicit form with member-access callee surfaces member name")
    func explicitMemberAccessCallee() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testMemberIdempotent() {
                let s = "hello"
                let once = formatter.normalize(s)
                let twice = formatter.normalize(once)
                XCTAssertEqual(once, twice)
            }
        }
        """
        let detections = AssertAfterDoubleApplyDetectorTests.detect(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.calleeName == "normalize")
    }

    @Test("Explicit form with mismatched callees is rejected")
    func explicitMismatchedCalleesRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testMixedCallees() {
                let s = "hello"
                let once = normalize(s)
                let twice = canonicalize(once)
                XCTAssertEqual(once, twice)
            }
        }
        """
        let detections = AssertAfterDoubleApplyDetectorTests.detect(in: source)
        #expect(detections.isEmpty)
    }

    // MARK: - Collapsed shape

    @Test("Collapsed XCTAssertEqual(f(f(x)), f(x)) is detected")
    func collapsedXCTAssertEqualLHS() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testCollapsedIdempotent() {
                let s = "hello"
                XCTAssertEqual(normalize(normalize(s)), normalize(s))
            }
        }
        """
        let detections = AssertAfterDoubleApplyDetectorTests.detect(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.calleeName == "normalize")
        #expect(detections.first?.inputBindingName == "s")
    }

    @Test("Collapsed XCTAssertEqual(f(x), f(f(x))) (other side) is detected")
    func collapsedXCTAssertEqualRHS() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testCollapsedIdempotentSwap() {
                let s = "hello"
                XCTAssertEqual(normalize(s), normalize(normalize(s)))
            }
        }
        """
        let detections = AssertAfterDoubleApplyDetectorTests.detect(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.calleeName == "normalize")
    }

    @Test("Collapsed #expect(f(f(x)) == f(x)) is detected")
    func collapsedExpectMacro() {
        let source = """
        import Testing
        @Test func swiftTestingCollapsedIdempotent() {
            let s = "hello"
            #expect(normalize(normalize(s)) == normalize(s))
        }
        """
        let detections = AssertAfterDoubleApplyDetectorTests.detect(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.calleeName == "normalize")
        #expect(detections.first?.inputBindingName == "s")
    }

    @Test("Collapsed #expect with member-access callees")
    func collapsedExpectMemberAccess() {
        let source = """
        import Testing
        @Test func memberIdempotent() {
            let s = "hello"
            #expect(formatter.normalize(formatter.normalize(s)) == formatter.normalize(s))
        }
        """
        let detections = AssertAfterDoubleApplyDetectorTests.detect(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.calleeName == "normalize")
    }

    @Test("Collapsed shape with mismatched callees is rejected")
    func collapsedMismatchedCalleesRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testMixed() {
                let s = "hello"
                XCTAssertEqual(normalize(canonicalize(s)), canonicalize(s))
            }
        }
        """
        let detections = AssertAfterDoubleApplyDetectorTests.detect(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Tautology XCTAssertEqual(f(s), f(s)) is rejected (no double-apply)")
    func tautologyRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testTautology() {
                let s = "hello"
                XCTAssertEqual(normalize(s), normalize(s))
            }
        }
        """
        let detections = AssertAfterDoubleApplyDetectorTests.detect(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Tautology #expect(f(s) == f(s)) is rejected")
    func tautologyExpectRejected() {
        let source = """
        import Testing
        @Test func tautologyExpect() {
            let s = "hello"
            #expect(normalize(s) == normalize(s))
        }
        """
        let detections = AssertAfterDoubleApplyDetectorTests.detect(in: source)
        #expect(detections.isEmpty)
    }

    // MARK: - Inputs that don't match the M2.1 shape

    @Test("Slice with no assertion → no detections")
    func noAssertionNoDetections() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testSetupOnly() {
                let s = "hello"
            }
        }
        """
        let detections = AssertAfterDoubleApplyDetectorTests.detect(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Round-trip shape is not surfaced as idempotence")
    func roundTripNotIdempotence() {
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
        // Round-trip has different callees on the two binding inits
        // (encode vs decode); the idempotence detector's single-callee
        // invariant rejects.
        let detections = AssertAfterDoubleApplyDetectorTests.detect(in: source)
        #expect(detections.isEmpty)
    }

    @Test("XCTAssertTrue is not anchored on for idempotence detection")
    func xctAssertTrueIgnored() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testAssertTrue() {
                let s = "hello"
                XCTAssertTrue(normalize(normalize(s)) == normalize(s))
            }
        }
        """
        // Mirror M1.3's posture — collapsed shape covers
        // XCTAssertEqual + #expect, not XCTAssertTrue.
        let detections = AssertAfterDoubleApplyDetectorTests.detect(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Inline literal as innermost input is not detected (binding-only posture)")
    func inlineLiteralInnerInputRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testInlineLiteral() {
                XCTAssertEqual(normalize(normalize("hello")), normalize("hello"))
            }
        }
        """
        // M1.3 has the same constraint — inner argument must be a
        // DeclReferenceExpr. Tests using inline literals can refactor
        // to bind first.
        let detections = AssertAfterDoubleApplyDetectorTests.detect(in: source)
        #expect(detections.isEmpty)
    }
}
