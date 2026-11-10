@testable import SwiftInferTestLifter
import Testing

@Suite("AssertOrderingPreservedDetector — Swift Testing two-#expect (M5.1)")
struct OrderingPreservedSwiftTestingTests {

    @Test("Per-shape (ii): collapsed two-#expect form is detected (non-strict result)")
    func swiftTestingNonStrictResult() {
        let source = """
        import Testing
        struct T {
            @Test
            func applyDiscountIsMonotonic() {
                let a = 5
                let b = 10
                #expect(a < b)
                #expect(applyDiscount(a) <= applyDiscount(b))
            }
        }
        """
        let detections = detectMonotonicity(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.calleeName == "applyDiscount")
        #expect(detections.first?.leftArgName == "a")
        #expect(detections.first?.rightArgName == "b")
    }

    @Test("Two-#expect form with strict result < is detected (same +20 signal)")
    func swiftTestingStrictResult() {
        let source = """
        import Testing
        struct T {
            @Test
            func strictlyMonotonic() {
                let a = 5
                let b = 10
                #expect(a < b)
                #expect(score(a) < score(b))
            }
        }
        """
        let detections = detectMonotonicity(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.calleeName == "score")
    }

    @Test("#expect tautology score(a) <= score(a) is rejected")
    func swiftTestingTautologyRejected() {
        let source = """
        import Testing
        struct T {
            @Test
            func tautology() {
                let a = 5
                #expect(score(a) <= score(a))
            }
        }
        """
        let detections = detectMonotonicity(in: source)
        #expect(detections.isEmpty)
    }

    @Test("#expect conclusion without #expect precondition is rejected")
    func swiftTestingConclusionWithoutPrecondition() {
        let source = """
        import Testing
        struct T {
            @Test
            func noPrecondition() {
                let a = 5
                let b = 10
                #expect(score(a) <= score(b))
            }
        }
        """
        let detections = detectMonotonicity(in: source)
        #expect(detections.isEmpty)
    }

    @Test("#expect mismatched callees are rejected")
    func swiftTestingMismatchedCalleesRejected() {
        let source = """
        import Testing
        struct T {
            @Test
            func mixedCallees() {
                let a = 5
                let b = 10
                #expect(a < b)
                #expect(score(a) <= rank(b))
            }
        }
        """
        let detections = detectMonotonicity(in: source)
        #expect(detections.isEmpty)
    }

    @Test("#expect with <= precondition (non-strict) is rejected — strict precondition required")
    func swiftTestingNonStrictPreconditionRejected() {
        let source = """
        import Testing
        struct T {
            @Test
            func nonStrictPrecondition() {
                let a = 5
                let b = 10
                #expect(a <= b)
                #expect(score(a) <= score(b))
            }
        }
        """
        let detections = detectMonotonicity(in: source)
        #expect(detections.isEmpty)
    }

    // MARK: - Empty / degenerate slices

    @Test("Empty body returns no detections")
    func emptyBody() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testEmpty() {
            }
        }
        """
        let detections = detectMonotonicity(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Body with unrelated XCTAssertEqual produces no monotonicity detection")
    func bodyWithEqualityAssertion() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testEquality() {
                let a = 5
                let b = a
                XCTAssertEqual(a, b)
            }
        }
        """
        let detections = detectMonotonicity(in: source)
        #expect(detections.isEmpty)
    }
}
