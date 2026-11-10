@testable import SwiftInferTestLifter
import Testing

@Suite("AsymmetricAssertionDetector — idempotence + commutativity negative (M7.0)")
struct AsymmetricIdempotenceCommutativityTests {

    @Test("XCTAssertNotEqual(f(f(x)), f(x)) → idempotence counter-signal")
    func xctestIdempotenceNegative() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testNotIdempotent() {
                let s = "hello"
                XCTAssertNotEqual(normalize(normalize(s)), normalize(s))
            }
        }
        """
        let detections = detectAsymmetric(in: source)
        if case .idempotence(let callee) = detections.first {
            #expect(callee == "normalize")
        } else {
            Issue.record("Expected .idempotence detection, got \(detections)")
        }
    }

    @Test("#expect(f(f(x)) != f(x)) → idempotence counter-signal")
    func swiftTestingIdempotenceNegative() {
        let source = """
        import Testing
        struct T {
            @Test
            func notIdempotent() {
                let s = "hello"
                #expect(normalize(normalize(s)) != normalize(s))
            }
        }
        """
        let detections = detectAsymmetric(in: source)
        #expect(detections.contains { detection in
            if case .idempotence = detection { return true }
            return false
        })
    }

    @Test("XCTAssertNotEqual(f(a, b), f(b, a)) → commutativity counter-signal")
    func xctestCommutativityNegative() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testNotCommutative() {
                let a = [1, 2]
                let b = [3, 4]
                XCTAssertNotEqual(merge(a, b), merge(b, a))
            }
        }
        """
        let detections = detectAsymmetric(in: source)
        #expect(detections.contains { detection in
            if case .commutativity(let callee) = detection {
                return callee == "merge"
            }
            return false
        })
    }
}
