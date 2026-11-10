@testable import SwiftInferTestLifter
import Testing

@Suite("AssertCountChangeDetector — empty / degenerate slices (M5.2)")
struct CountChangeDegenerateTests {

    @Test("Empty body returns no detections")
    func emptyBody() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testEmpty() {
            }
        }
        """
        let detections = detectCountInvariance(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Body with unrelated assertion produces no count-invariance detection")
    func bodyWithUnrelatedAssertion() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testUnrelated() {
                let xs = [1, 2, 3]
                let ys = filter(xs)
                XCTAssertEqual(ys, [1, 2])
            }
        }
        """
        let detections = detectCountInvariance(in: source)
        #expect(detections.isEmpty)
    }

    @Test("XCTAssertTrue is not a recognized shape (assertion kind narrowed to ==)")
    func xctAssertTrueNotRecognized() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testAssertTrue() {
                let xs = [1, 2, 3]
                XCTAssertTrue(filter(xs).count == xs.count)
            }
        }
        """
        let detections = detectCountInvariance(in: source)
        #expect(detections.isEmpty)
    }
}
