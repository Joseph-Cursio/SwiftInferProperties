import Testing
@testable import SwiftInferTestLifter

private func detectMonotonicity(in source: String) -> [DetectedMonotonicity] {
    let slice = SlicerTestHelper.sliceFirstBody(in: source)
    return AssertOrderingPreservedDetector.detect(in: slice)
}

@Suite("AssertOrderingPreservedDetector — XCTest two-assert (M5.1)")
struct OrderingPreservedXCTestTests {

    @Test("Per-shape (i): explicit two-assert XCTAssert pair is detected")
    func xctestExplicitTwoAssert() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testApplyDiscountIsMonotonic() {
                let a = 5
                let b = 10
                XCTAssertLessThan(a, b)
                XCTAssertLessThanOrEqual(applyDiscount(a), applyDiscount(b))
            }
        }
        """
        let detections = detectMonotonicity(in: source)
        #expect(detections.count == 1)
        let detected = detections.first
        #expect(detected?.calleeName == "applyDiscount")
        #expect(detected?.leftArgName == "a")
        #expect(detected?.rightArgName == "b")
    }

    @Test("Per-shape (iii): strict-inequality result XCTAssertLessThan(f(a), f(b)) is detected")
    func xctestStrictResult() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testStrictlyMonotonic() {
                let a = 5
                let b = 10
                XCTAssertLessThan(a, b)
                XCTAssertLessThan(score(a), score(b))
            }
        }
        """
        let detections = detectMonotonicity(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.calleeName == "score")
    }

    @Test("Member-access callee surfaces member name (parity with other M5 detectors)")
    func xctestMemberAccessCallee() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testMemberMonotonic() {
                let a = 5
                let b = 10
                XCTAssertLessThan(a, b)
                XCTAssertLessThanOrEqual(pricing.discount(a), pricing.discount(b))
            }
        }
        """
        let detections = detectMonotonicity(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.calleeName == "discount")
    }

    @Test("Per-shape (v): mismatched callees are rejected")
    func xctestMismatchedCalleesRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testMixedCallees() {
                let a = 5
                let b = 10
                XCTAssertLessThan(a, b)
                XCTAssertLessThanOrEqual(score(a), rank(b))
            }
        }
        """
        let detections = detectMonotonicity(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Per-shape (iv): tautology f(a) <= f(a) without precondition asymmetry is rejected")
    func xctestTautologyRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testTautology() {
                let a = 5
                XCTAssertLessThanOrEqual(score(a), score(a))
            }
        }
        """
        let detections = detectMonotonicity(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Conclusion without matching precondition is rejected (no XCTAssertLessThan precondition)")
    func xctestConclusionWithoutPreconditionRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testNoPrecondition() {
                let a = 5
                let b = 10
                XCTAssertLessThanOrEqual(score(a), score(b))
            }
        }
        """
        let detections = detectMonotonicity(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Precondition with non-matching arg names doesn't pair with conclusion")
    func xctestPreconditionArgsDontMatch() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testWrongPreconditionArgs() {
                let a = 5
                let b = 10
                let c = 20
                XCTAssertLessThan(c, b)
                XCTAssertLessThanOrEqual(score(a), score(b))
            }
        }
        """
        let detections = detectMonotonicity(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Reversed argument order in conclusion (f(b), f(a)) is rejected — anti-monotonicity not in scope")
    func xctestReversedConclusionRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testAntiMonotonic() {
                let a = 5
                let b = 10
                XCTAssertLessThan(a, b)
                XCTAssertLessThanOrEqual(score(b), score(a))
            }
        }
        """
        let detections = detectMonotonicity(in: source)
        #expect(detections.isEmpty)
    }

}

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
