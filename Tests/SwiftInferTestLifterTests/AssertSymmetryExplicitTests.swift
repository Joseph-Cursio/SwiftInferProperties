@testable import SwiftInferTestLifter
import Testing

@Suite("AssertSymmetryDetector — explicit commutativity (M2.2)")
struct AssertSymmetryExplicitTests {

    @Test("Explicit three-line commutativity is detected")
    func explicitCommutativity() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testMergeIsCommutative() {
                let a = [1, 2]
                let b = [3, 4]
                let lhs = merge(a, b)
                let rhs = merge(b, a)
                XCTAssertEqual(lhs, rhs)
            }
        }
        """
        let detections = detect(in: source)
        #expect(detections.count == 1)
        let detected = detections.first
        #expect(detected?.calleeName == "merge")
        #expect(detected?.leftArgName == "a")
        #expect(detected?.rightArgName == "b")
    }

    @Test("Explicit form with member-access callee surfaces member name")
    func explicitMemberAccessCallee() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testUnionCommutative() {
                let a: Set<Int> = [1, 2]
                let b: Set<Int> = [3, 4]
                let lhs = a.union(b)
                let rhs = b.union(a)
                XCTAssertEqual(lhs, rhs)
            }
        }
        """
        let detections = detect(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.calleeName == "union")
    }

    @Test("Explicit form with mismatched callees is rejected")
    func explicitMismatchedCalleesRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testMixedCallees() {
                let a = [1, 2]
                let b = [3, 4]
                let lhs = merge(a, b)
                let rhs = combine(b, a)
                XCTAssertEqual(lhs, rhs)
            }
        }
        """
        #expect(detect(in: source).isEmpty)
    }

    @Test("Explicit form without argument reversal is rejected")
    func explicitNoReversalRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testSameOrder() {
                let a = [1, 2]
                let b = [3, 4]
                let lhs = merge(a, b)
                let rhs = merge(a, b)
                XCTAssertEqual(lhs, rhs)
            }
        }
        """
        #expect(detect(in: source).isEmpty)
    }
}
