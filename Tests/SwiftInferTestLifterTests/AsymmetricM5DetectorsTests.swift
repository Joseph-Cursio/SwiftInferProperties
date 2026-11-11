@testable import SwiftInferTestLifter
import Testing

func detectAsymmetric(in source: String) -> [DetectedAsymmetricAssertion] {
    let slice = SlicerTestHelper.sliceFirstBody(in: source)
    return AsymmetricAssertionDetector.detect(in: slice)
}

@Suite("AsymmetricAssertionDetector — monotonicity / count / reduce negative (M7.0)")
struct AsymmetricM5DetectorsTests {

    @Test("XCTAssertLessThan(a, b); XCTAssertGreaterThan(f(a), f(b)) → anti-monotonicity")
    func xctestAntiMonotonicity() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testAntiMonotonic() {
                let a = 5
                let b = 10
                XCTAssertLessThan(a, b)
                XCTAssertGreaterThan(score(a), score(b))
            }
        }
        """
        let detections = detectAsymmetric(in: source)
        #expect(detections.contains { detection in
            if case .monotonicity(let callee) = detection {
                return callee == "score"
            }
            return false
        })
    }

    @Test("#expect(a < b); #expect(f(a) > f(b)) → anti-monotonicity")
    func swiftTestingAntiMonotonicity() {
        let source = """
        import Testing
        struct T {
            @Test
            func antiMonotonic() {
                let a = 5
                let b = 10
                #expect(a < b)
                #expect(score(a) > score(b))
            }
        }
        """
        let detections = detectAsymmetric(in: source)
        #expect(detections.contains { detection in
            if case .monotonicity = detection { return true }
            return false
        })
    }

    @Test("XCTAssertNotEqual(filter(xs).count, xs.count) → count-invariance counter-signal")
    func xctestCountInvarianceNegative() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testCountChanges() {
                let xs = [1, 2, 3]
                XCTAssertNotEqual(filter(xs).count, xs.count)
            }
        }
        """
        let detections = detectAsymmetric(in: source)
        #expect(detections.contains { detection in
            if case .countInvariance(let callee) = detection {
                return callee == "filter"
            }
            return false
        })
    }

    @Test("XCTAssertNotEqual(xs.reduce(0, +), xs.reversed().reduce(0, +)) → reduce-equivalence")
    func xctestReduceEquivalenceNegative() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testReduceNotInvariant() {
                let xs = [1, 2, 3]
                XCTAssertNotEqual(xs.reduce(0, -), xs.reversed().reduce(0, -))
            }
        }
        """
        let detections = detectAsymmetric(in: source)
        #expect(detections.contains { detection in
            if case .reduceEquivalence(let opName) = detection {
                return opName == "-"
            }
            return false
        })
    }
}
