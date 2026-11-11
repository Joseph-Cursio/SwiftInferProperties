@testable import SwiftInferTestLifter
import Testing

@Suite("AssertReduceEquivalenceDetector — explicit shape (M5.3)")
struct ReduceEquivalenceExplicitTests {

    @Test("Per-shape (iii): explicit two-binding form is detected")
    func explicitTwoBinding() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testExplicitForm() {
                let xs = [1, 2, 3]
                let lhs = xs.reduce(0, +)
                let rhs = xs.reversed().reduce(0, +)
                XCTAssertEqual(lhs, rhs)
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

    @Test("Explicit two-binding with named op (combine) is detected")
    func explicitNamedOp() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testExplicitCombine() {
                let items = [1, 2, 3]
                let lhs = items.reduce(.zero, combine)
                let rhs = items.reversed().reduce(.zero, combine)
                XCTAssertEqual(lhs, rhs)
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.opCalleeName == "combine")
        #expect(detections.first?.seedSource == ".zero")
    }

    @Test("Explicit form with reversed assertion order XCTAssertEqual(rhs, lhs) is detected")
    func explicitReversedAssertionOrder() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testExplicitReversed() {
                let xs = [1, 2, 3]
                let lhs = xs.reduce(0, +)
                let rhs = xs.reversed().reduce(0, +)
                XCTAssertEqual(rhs, lhs)
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.opCalleeName == "+")
    }

    @Test("Explicit form rejects when binding initializer is not a reduce call")
    func explicitNonReduceBindingRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testNonReduceBinding() {
                let xs = [1, 2, 3]
                let lhs = xs.first ?? 0
                let rhs = xs.reversed().reduce(0, +)
                XCTAssertEqual(lhs, rhs)
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Explicit form rejects when both bindings are direct (no .reversed())")
    func explicitBothDirectRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testBothDirect() {
                let xs = [1, 2, 3]
                let lhs = xs.reduce(0, +)
                let rhs = xs.reduce(0, +)
                XCTAssertEqual(lhs, rhs)
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Explicit form rejects when ops differ across bindings")
    func explicitDifferentOpsRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testDifferentOps() {
                let xs = [1, 2, 3]
                let lhs = xs.reduce(0, +)
                let rhs = xs.reversed().reduce(0, *)
                XCTAssertEqual(lhs, rhs)
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Explicit form is XCTest-only (mirrors M2.1 posture); #expect with bindings is not detected")
    func explicitSwiftTestingRejected() {
        let source = """
        import Testing
        struct T {
            @Test
            func explicitWithExpect() {
                let xs = [1, 2, 3]
                let lhs = xs.reduce(0, +)
                let rhs = xs.reversed().reduce(0, +)
                #expect(lhs == rhs)
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }
}
