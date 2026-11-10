@testable import SwiftInferTestLifter
import Testing

@Suite("AssertReduceEquivalenceDetector — empty / degenerate slices (M5.3)")
struct ReduceEquivalenceDegenerateTests {

    @Test("Empty body returns no detections")
    func emptyBody() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testEmpty() {
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Body with unrelated assertion produces no detection")
    func bodyWithUnrelatedAssertion() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testUnrelated() {
                let xs = [1, 2, 3]
                XCTAssertEqual(xs.count, 3)
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }

    @Test("XCTAssertTrue is not a recognized shape (assertion kind narrowed to ==)")
    func xctAssertTrueNotRecognized() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testAssertTrue() {
                let xs = [1, 2, 3]
                XCTAssertTrue(xs.reduce(0, +) == xs.reversed().reduce(0, +))
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }
}
