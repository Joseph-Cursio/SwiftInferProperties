import Testing
@testable import SwiftInferTestLifter

private func detectAsymmetric(in source: String) -> [DetectedAsymmetricAssertion] {
    let slice = SlicerTestHelper.sliceFirstBody(in: source)
    return AsymmetricAssertionDetector.detect(in: slice)
}

@Suite("AsymmetricAssertionDetector — round-trip negative (M7.0)")
struct AsymmetricRoundTripNegativeTests {

    @Test("XCTAssertNotEqual(decode(encode(x)), x) → counter-signal")
    func xctestRoundTripNegative() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testRoundTripBroken() {
                let x = 42
                XCTAssertNotEqual(decode(encode(x)), x)
            }
        }
        """
        let detections = detectAsymmetric(in: source)
        #expect(detections.count == 1)
        if case .roundTrip(let forward, let backward) = detections.first {
            #expect(forward == "encode")
            #expect(backward == "decode")
        } else {
            Issue.record("Expected .roundTrip detection")
        }
    }

    @Test("#expect(decode(encode(x)) != x) → counter-signal")
    func swiftTestingRoundTripNegative() {
        let source = """
        import Testing
        struct T {
            @Test
            func roundTripBroken() {
                let x = 42
                #expect(decode(encode(x)) != x)
            }
        }
        """
        let detections = detectAsymmetric(in: source)
        #expect(detections.count == 1)
    }

    @Test("Same-callee XCTAssertNotEqual is rejected (idempotence shape, not round-trip)")
    func sameCallleRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testIdempotenceBroken() {
                let x = 42
                XCTAssertNotEqual(f(f(x)), f(x))
            }
        }
        """
        let detections = detectAsymmetric(in: source)
        // Should fire as idempotence-negative, not round-trip.
        #expect(detections.contains { detection in
            if case .idempotence = detection { return true }
            return false
        })
        #expect(!detections.contains { detection in
            if case .roundTrip = detection { return true }
            return false
        })
    }
}

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
