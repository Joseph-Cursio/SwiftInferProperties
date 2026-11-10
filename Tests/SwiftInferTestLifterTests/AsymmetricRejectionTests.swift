@testable import SwiftInferTestLifter
import Testing

@Suite("AsymmetricAssertionDetector — negative cases (M7.0)")
struct AsymmetricRejectionTests {

    @Test("Positive XCTAssertEqual does not fire any counter-signal")
    func positiveAssertionDoesNotFire() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testPositive() {
                let x = 42
                XCTAssertEqual(decode(encode(x)), x)
            }
        }
        """
        let detections = detectAsymmetric(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Tautology XCTAssertNotEqual(x, x) does not fire")
    func tautologyDoesNotFire() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testTautology() {
                let x = 42
                XCTAssertNotEqual(x, x)
            }
        }
        """
        let detections = detectAsymmetric(in: source)
        #expect(detections.isEmpty)
    }

    @Test("XCTAssertGreaterThan without strict-< precondition does not fire monotonicity-negative")
    func antiMonotonicityWithoutPreconditionRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testNoPrecondition() {
                let a = 5
                let b = 10
                XCTAssertGreaterThan(score(a), score(b))
            }
        }
        """
        let detections = detectAsymmetric(in: source)
        #expect(!detections.contains { detection in
            if case .monotonicity = detection { return true }
            return false
        })
    }

    @Test("Empty body returns no detections")
    func emptyBody() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testEmpty() {
            }
        }
        """
        let detections = detectAsymmetric(in: source)
        #expect(detections.isEmpty)
    }
}
