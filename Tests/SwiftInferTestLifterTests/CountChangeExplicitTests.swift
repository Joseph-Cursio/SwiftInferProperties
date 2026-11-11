@testable import SwiftInferTestLifter
import Testing

@Suite("AssertCountChangeDetector — explicit shape (M5.2)")
struct CountChangeExplicitTests {

    @Test("Per-shape (iii): explicit two-binding form is detected")
    func explicitTwoBinding() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testExplicitForm() {
                let xs = [1, 2, 3]
                let result = transform(xs)
                XCTAssertEqual(result.count, xs.count)
            }
        }
        """
        let detections = detectCountInvariance(in: source)
        #expect(detections.count == 1)
        let detected = detections.first
        #expect(detected?.calleeName == "transform")
        #expect(detected?.inputBindingName == "xs")
    }

    @Test("Explicit form with reversed assertion order XCTAssertEqual(xs.count, result.count) is detected")
    func explicitReversedAssertionOrder() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testReversed() {
                let xs = [1, 2, 3]
                let result = filter(xs)
                XCTAssertEqual(xs.count, result.count)
            }
        }
        """
        let detections = detectCountInvariance(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.calleeName == "filter")
        #expect(detections.first?.inputBindingName == "xs")
    }

    @Test("Explicit form rejects when binding initializer is not a function call")
    func explicitNonFunctionCallBinding() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testNonCallBinding() {
                let xs = [1, 2, 3]
                let result = xs
                XCTAssertEqual(result.count, xs.count)
            }
        }
        """
        let detections = detectCountInvariance(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Explicit form rejects when binding's first arg doesn't match the bare-input side")
    func explicitArgumentMismatchRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testArgMismatch() {
                let xs = [1, 2, 3]
                let ys = [4, 5, 6]
                let result = filter(xs)
                XCTAssertEqual(result.count, ys.count)
            }
        }
        """
        let detections = detectCountInvariance(in: source)
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
                let result = filter(xs)
                #expect(result.count == xs.count)
            }
        }
        """
        let detections = detectCountInvariance(in: source)
        #expect(detections.isEmpty)
    }
}
