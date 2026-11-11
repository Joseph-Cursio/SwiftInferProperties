@testable import SwiftInferTestLifter
import Testing

func detectReduceEquivalence(in source: String) -> [DetectedReduceEquivalence] {
    let slice = SlicerTestHelper.sliceFirstBody(in: source)
    return AssertReduceEquivalenceDetector.detect(in: slice)
}

@Suite("AssertReduceEquivalenceDetector — collapsed shape (M5.3)")
struct ReduceEquivalenceCollapsedTests {

    @Test("Per-shape (i): collapsed XCTAssertEqual with operator op (+) is detected")
    func collapsedXCTestOperatorOp() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testSumReduceIsAssociative() {
                let xs = [1, 2, 3, 4]
                XCTAssertEqual(xs.reduce(0, +), xs.reversed().reduce(0, +))
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.count == 1)
        let detected = detections.first
        #expect(detected?.opCalleeName == "+")
        #expect(detected?.seedSource == "0")
        #expect(detected?.collectionBindingName == "xs")
    }

    @Test("Per-shape (ii): collapsed #expect with named-function op (combine) is detected")
    func collapsedSwiftTestingNamedOp() {
        let source = """
        import Testing
        struct T {
            @Test
            func combineIsAssociative() {
                let items = [1, 2, 3]
                #expect(items.reduce(.zero, combine) == items.reversed().reduce(.zero, combine))
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.count == 1)
        let detected = detections.first
        #expect(detected?.opCalleeName == "combine")
        #expect(detected?.seedSource == ".zero")
        #expect(detected?.collectionBindingName == "items")
    }

    @Test("Reversed argument order (xs.reversed() on lhs, direct on rhs) is detected")
    func collapsedReversedArgumentOrder() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testReversedFirst() {
                let xs = [1, 2, 3]
                XCTAssertEqual(xs.reversed().reduce(0, +), xs.reduce(0, +))
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.opCalleeName == "+")
    }

    @Test("Per-shape (iv): tautology with no .reversed() on either side is rejected")
    func tautologyNoReversedRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testTautology() {
                let xs = [1, 2, 3]
                XCTAssertEqual(xs.reduce(0, +), xs.reduce(0, +))
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Both-reversed shape (.reversed() on both sides) is rejected")
    func bothReversedRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testBothReversed() {
                let xs = [1, 2, 3]
                XCTAssertEqual(xs.reversed().reduce(0, +), xs.reversed().reduce(0, +))
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Per-shape (v): different ops (+, *) are rejected")
    func differentOpsRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testDifferentOps() {
                let xs = [1, 2, 3]
                XCTAssertEqual(xs.reduce(0, +), xs.reversed().reduce(0, *))
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Different seeds (0 vs 1) are rejected")
    func differentSeedsRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testDifferentSeeds() {
                let xs = [1, 2, 3]
                XCTAssertEqual(xs.reduce(0, +), xs.reversed().reduce(1, +))
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Different collection identifiers (xs vs ys) are rejected")
    func differentCollectionsRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testDifferentCollections() {
                let xs = [1, 2, 3]
                let ys = [4, 5, 6]
                XCTAssertEqual(xs.reduce(0, +), ys.reversed().reduce(0, +))
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Closure op (not a DeclRef) is rejected — closures deferred")
    func closureOpRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testClosureOp() {
                let xs = [1, 2, 3]
                XCTAssertEqual(
                    xs.reduce(0, { acc, x in acc + x }),
                    xs.reversed().reduce(0, { acc, x in acc + x })
                )
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Three-arg .reduce(into:_:_:)-shaped call (count != 2) is rejected")
    func threeArgReduceRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testThreeArg() {
                let xs = [1, 2, 3]
                XCTAssertEqual(xs.reduce(0, +, +), xs.reversed().reduce(0, +, +))
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }
}
