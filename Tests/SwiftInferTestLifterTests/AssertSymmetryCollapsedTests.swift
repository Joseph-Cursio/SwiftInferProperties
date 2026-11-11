@testable import SwiftInferTestLifter
import Testing

@Suite("AssertSymmetryDetector — collapsed commutativity (M2.2)")
struct AssertSymmetryCollapsedTests {

    @Test("Collapsed XCTAssertEqual(f(a, b), f(b, a)) is detected")
    func collapsedXCTAssertEqual() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testCollapsedMerge() {
                let a = [1, 2]
                let b = [3, 4]
                XCTAssertEqual(merge(a, b), merge(b, a))
            }
        }
        """
        let detections = detect(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.calleeName == "merge")
        #expect(detections.first?.leftArgName == "a")
        #expect(detections.first?.rightArgName == "b")
    }

    @Test("Collapsed XCTAssertEqual(f(b, a), f(a, b)) (swapped) is detected")
    func collapsedXCTAssertEqualSwapped() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testCollapsedSwap() {
                let a = [1, 2]
                let b = [3, 4]
                XCTAssertEqual(merge(b, a), merge(a, b))
            }
        }
        """
        let detections = detect(in: source)
        #expect(detections.count == 1)
        // When lhs is f(b, a), the "lhs" leftArg is b, rightArg is a.
        #expect(detections.first?.leftArgName == "b")
        #expect(detections.first?.rightArgName == "a")
    }

    @Test("Collapsed #expect(f(s1, s2) == f(s2, s1)) is detected")
    func collapsedExpectMacro() {
        let source = """
        import Testing
        @Test func unionCommutative() {
            let s1: Set<Int> = [1, 2]
            let s2: Set<Int> = [3, 4]
            #expect(union(s1, s2) == union(s2, s1))
        }
        """
        let detections = detect(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.calleeName == "union")
        #expect(detections.first?.leftArgName == "s1")
        #expect(detections.first?.rightArgName == "s2")
    }

    @Test("Collapsed shape with member-access callees")
    func collapsedMemberAccess() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testCollapsedMembers() {
                let a: Set<Int> = [1, 2]
                let b: Set<Int> = [3, 4]
                XCTAssertEqual(a.union(b), b.union(a))
            }
        }
        """
        let detections = detect(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.calleeName == "union")
    }

    @Test("Collapsed shape with mismatched callees is rejected")
    func collapsedMismatchedCalleesRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testMixed() {
                let a = [1, 2]
                let b = [3, 4]
                XCTAssertEqual(merge(a, b), combine(b, a))
            }
        }
        """
        #expect(detect(in: source).isEmpty)
    }
}
