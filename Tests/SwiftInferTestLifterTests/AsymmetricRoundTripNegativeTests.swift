@testable import SwiftInferTestLifter
import Testing

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
        if case let .roundTrip(forward, backward) = detections.first {
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
