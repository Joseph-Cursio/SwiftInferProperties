@testable import SwiftInferTestLifter
import Testing

func detectCountInvariance(in source: String) -> [DetectedCountInvariance] {
    let slice = SlicerTestHelper.sliceFirstBody(in: source)
    return AssertCountChangeDetector.detect(in: slice)
}

@Suite("AssertCountChangeDetector — collapsed shape (M5.2)")
struct CountChangeCollapsedTests {

    @Test("Per-shape (i): collapsed XCTAssertEqual(filter(xs).count, xs.count) is detected")
    func xctestCollapsedFilter() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testFilterPreservesCount() {
                let xs = [1, 2, 3, 4]
                XCTAssertEqual(filter(xs).count, xs.count)
            }
        }
        """
        let detections = detectCountInvariance(in: source)
        #expect(detections.count == 1)
        let detected = detections.first
        #expect(detected?.calleeName == "filter")
        #expect(detected?.inputBindingName == "xs")
    }

    @Test("Per-shape (ii): collapsed #expect(map(xs).count == xs.count) is detected")
    func swiftTestingCollapsedMap() {
        let source = """
        import Testing
        struct T {
            @Test
            func mapPreservesCount() {
                let xs = [1, 2, 3]
                #expect(map(xs).count == xs.count)
            }
        }
        """
        let detections = detectCountInvariance(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.calleeName == "map")
        #expect(detections.first?.inputBindingName == "xs")
    }

    @Test("Reversed argument order in collapsed XCTAssertEqual(xs.count, filter(xs).count) is detected")
    func xctestCollapsedReversedOrder() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testReversedOrder() {
                let xs = [1, 2, 3]
                XCTAssertEqual(xs.count, filter(xs).count)
            }
        }
        """
        let detections = detectCountInvariance(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.calleeName == "filter")
    }

    @Test("Member-access callee surfaces member name (parity with other M5 detectors)")
    func collapsedMemberAccessCallee() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testMemberCount() {
                let xs = [1, 2, 3]
                XCTAssertEqual(pricing.filter(xs).count, xs.count)
            }
        }
        """
        let detections = detectCountInvariance(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.calleeName == "filter")
    }

    @Test("Per-shape (iv): tautology XCTAssertEqual(xs.count, xs.count) is rejected")
    func tautologyRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testTautology() {
                let xs = [1, 2, 3]
                XCTAssertEqual(xs.count, xs.count)
            }
        }
        """
        let detections = detectCountInvariance(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Per-shape (v): different keyPath XCTAssertEqual(f(xs).first, xs.first) is rejected")
    func differentKeyPathRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testFirstNotCount() {
                let xs = [1, 2, 3]
                XCTAssertEqual(filter(xs).first, xs.first)
            }
        }
        """
        let detections = detectCountInvariance(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Mismatched input identifier XCTAssertEqual(filter(xs).count, ys.count) is rejected")
    func mismatchedInputIdentifierRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testMismatchedInput() {
                let xs = [1, 2, 3]
                let ys = [4, 5, 6]
                XCTAssertEqual(filter(xs).count, ys.count)
            }
        }
        """
        let detections = detectCountInvariance(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Both sides are function calls (no bare-input side) — rejected")
    func bothSidesFunctionCallsRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testBothTransformed() {
                let xs = [1, 2, 3]
                XCTAssertEqual(filter(xs).count, map(xs).count)
            }
        }
        """
        let detections = detectCountInvariance(in: source)
        #expect(detections.isEmpty)
    }

    @Test("#expect(filter(xs).count == ys.count) — mismatched bare-input identifier rejected")
    func swiftTestingMismatchedInputRejected() {
        let source = """
        import Testing
        struct T {
            @Test
            func mismatched() {
                let xs = [1, 2, 3]
                let ys = [4, 5, 6]
                #expect(filter(xs).count == ys.count)
            }
        }
        """
        let detections = detectCountInvariance(in: source)
        #expect(detections.isEmpty)
    }

    @Test("#expect tautology xs.count == xs.count is rejected")
    func swiftTestingTautologyRejected() {
        let source = """
        import Testing
        struct T {
            @Test
            func tautology() {
                let xs = [1, 2, 3]
                #expect(xs.count == xs.count)
            }
        }
        """
        let detections = detectCountInvariance(in: source)
        #expect(detections.isEmpty)
    }
}
