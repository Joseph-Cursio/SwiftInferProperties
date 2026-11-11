@testable import SwiftInferTestLifter
import Testing

func detect(in source: String) -> [DetectedCommutativity] {
    let slice = SlicerTestHelper.sliceFirstBody(in: source)
    return AssertSymmetryDetector.detect(in: slice)
}

@Suite("AssertSymmetryDetector — rejection cases (M2.2)")
struct AssertSymmetryRejectionTests {

    @Test("Tautology XCTAssertEqual(f(a, a), f(a, a)) is rejected")
    func tautologyRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testTautology() {
                let a = [1, 2]
                XCTAssertEqual(merge(a, a), merge(a, a))
            }
        }
        """
        #expect(detect(in: source).isEmpty)
    }

    @Test("Tautology #expect(f(a, a) == f(a, a)) is rejected")
    func tautologyExpectRejected() {
        let source = """
        import Testing
        @Test func tautologyExpect() {
            let a = [1, 2]
            #expect(merge(a, a) == merge(a, a))
        }
        """
        #expect(detect(in: source).isEmpty)
    }

    @Test("No-reversal collapsed shape XCTAssertEqual(f(a, b), f(a, b)) is rejected")
    func noReversalCollapsedRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testNoReversal() {
                let a = [1, 2]
                let b = [3, 4]
                XCTAssertEqual(merge(a, b), merge(a, b))
            }
        }
        """
        #expect(detect(in: source).isEmpty)
    }

    @Test("Slice with no assertion → no detections")
    func noAssertionNoDetections() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testSetupOnly() {
                let a = [1, 2]
            }
        }
        """
        #expect(detect(in: source).isEmpty)
    }

    @Test("Round-trip shape is not surfaced as commutativity")
    func roundTripNotCommutativity() {
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
        // Round-trip's assertion args are bare identifiers (not call
        // expressions) bound to single-argument calls — fails the
        // commutativity detector's two-argument-call shape check.
        #expect(detect(in: source).isEmpty)
    }

    @Test("Idempotence shape is not surfaced as commutativity")
    func idempotenceNotCommutativity() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testIdempotent() {
                let s = "hello"
                XCTAssertEqual(normalize(normalize(s)), normalize(s))
            }
        }
        """
        // Idempotence's call-site shape is single-arg — fails the
        // two-argument shape check.
        #expect(detect(in: source).isEmpty)
    }

    @Test("XCTAssertTrue is not anchored on for commutativity detection")
    func xctAssertTrueIgnored() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testAssertTrue() {
                let a = [1, 2]
                let b = [3, 4]
                XCTAssertTrue(merge(a, b) == merge(b, a))
            }
        }
        """
        #expect(detect(in: source).isEmpty)
    }

    @Test("Inline-literal arguments are not detected (binding-only posture)")
    func inlineLiteralArgsRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testInlineLiterals() {
                XCTAssertEqual(merge(1, 2), merge(2, 1))
            }
        }
        """
        // Mirror M1.3 / M2.1 — argument identifiers must be
        // DeclReferenceExpr. Tests using inline literals can refactor
        // to bind first.
        #expect(detect(in: source).isEmpty)
    }

    @Test("Three-argument call is not detected (mirrors §5.2 two-parameter shape)")
    func threeArgumentRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testThreeArgs() {
                let a = 1
                let b = 2
                let c = 3
                XCTAssertEqual(merge(a, b, c), merge(b, a, c))
            }
        }
        """
        // Per the M2 plan's open decision #6 default: literal reversal
        // of TWO arguments only. Three-or-more is out of scope for the
        // commutativity template.
        #expect(detect(in: source).isEmpty)
    }
}
