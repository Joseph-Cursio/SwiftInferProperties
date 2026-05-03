import Testing
@testable import SwiftInferTestLifter

private func detect(in source: String) -> [DetectedCommutativity] {
    let slice = SlicerTestHelper.sliceFirstBody(in: source)
    return AssertSymmetryDetector.detect(in: slice)
}

@Suite("AssertSymmetryDetector — explicit commutativity (M2.2)")
struct AssertSymmetryExplicitTests {

    @Test("Explicit three-line commutativity is detected")
    func explicitCommutativity() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testMergeIsCommutative() {
                let a = [1, 2]
                let b = [3, 4]
                let lhs = merge(a, b)
                let rhs = merge(b, a)
                XCTAssertEqual(lhs, rhs)
            }
        }
        """
        let detections = detect(in: source)
        #expect(detections.count == 1)
        let detected = detections.first
        #expect(detected?.calleeName == "merge")
        #expect(detected?.leftArgName == "a")
        #expect(detected?.rightArgName == "b")
    }

    @Test("Explicit form with member-access callee surfaces member name")
    func explicitMemberAccessCallee() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testUnionCommutative() {
                let a: Set<Int> = [1, 2]
                let b: Set<Int> = [3, 4]
                let lhs = a.union(b)
                let rhs = b.union(a)
                XCTAssertEqual(lhs, rhs)
            }
        }
        """
        let detections = detect(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.calleeName == "union")
    }

    @Test("Explicit form with mismatched callees is rejected")
    func explicitMismatchedCalleesRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testMixedCallees() {
                let a = [1, 2]
                let b = [3, 4]
                let lhs = merge(a, b)
                let rhs = combine(b, a)
                XCTAssertEqual(lhs, rhs)
            }
        }
        """
        #expect(detect(in: source).isEmpty)
    }

    @Test("Explicit form without argument reversal is rejected")
    func explicitNoReversalRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testSameOrder() {
                let a = [1, 2]
                let b = [3, 4]
                let lhs = merge(a, b)
                let rhs = merge(a, b)
                XCTAssertEqual(lhs, rhs)
            }
        }
        """
        #expect(detect(in: source).isEmpty)
    }
}

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

@Suite("AssertSymmetryDetector — rejection cases (M2.2)")
struct AssertSymmetryRejectionTests {

    @Test("Tautology XCTAssertEqual(f(a, a), f(a, a)) is rejected")
    func tautologyRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testTautology() {
                let a = [1, 2]
                XCTAssertEqual(merge(a, a), merge(a, a))
            }
        }
        """
        #expect(detect(in: source).isEmpty)
    }

    @Test("Tautology #expect(f(a, a) == f(a, a)) is rejected")
    func tautologyExpectRejected() {
        let source = """
        import Testing
        @Test func tautologyExpect() {
            let a = [1, 2]
            #expect(merge(a, a) == merge(a, a))
        }
        """
        #expect(detect(in: source).isEmpty)
    }

    @Test("No-reversal collapsed shape XCTAssertEqual(f(a, b), f(a, b)) is rejected")
    func noReversalCollapsedRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testNoReversal() {
                let a = [1, 2]
                let b = [3, 4]
                XCTAssertEqual(merge(a, b), merge(a, b))
            }
        }
        """
        #expect(detect(in: source).isEmpty)
    }

    @Test("Slice with no assertion → no detections")
    func noAssertionNoDetections() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testSetupOnly() {
                let a = [1, 2]
            }
        }
        """
        #expect(detect(in: source).isEmpty)
    }

    @Test("Round-trip shape is not surfaced as commutativity")
    func roundTripNotCommutativity() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testRoundTrip() {
                let original = 42
                let encoded = encode(original)
                let decoded = decode(encoded)
                XCTAssertEqual(original, decoded)
            }
        }
        """
        // Round-trip's assertion args are bare identifiers (not call
        // expressions) bound to single-argument calls — fails the
        // commutativity detector's two-argument-call shape check.
        #expect(detect(in: source).isEmpty)
    }

    @Test("Idempotence shape is not surfaced as commutativity")
    func idempotenceNotCommutativity() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testIdempotent() {
                let s = "hello"
                XCTAssertEqual(normalize(normalize(s)), normalize(s))
            }
        }
        """
        // Idempotence's call-site shape is single-arg — fails the
        // two-argument shape check.
        #expect(detect(in: source).isEmpty)
    }

    @Test("XCTAssertTrue is not anchored on for commutativity detection")
    func xctAssertTrueIgnored() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testAssertTrue() {
                let a = [1, 2]
                let b = [3, 4]
                XCTAssertTrue(merge(a, b) == merge(b, a))
            }
        }
        """
        #expect(detect(in: source).isEmpty)
    }

    @Test("Inline-literal arguments are not detected (binding-only posture)")
    func inlineLiteralArgsRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testInlineLiterals() {
                XCTAssertEqual(merge(1, 2), merge(2, 1))
            }
        }
        """
        // Mirror M1.3 / M2.1 — argument identifiers must be
        // DeclReferenceExpr. Tests using inline literals can refactor
        // to bind first.
        #expect(detect(in: source).isEmpty)
    }

    @Test("Three-argument call is not detected (mirrors §5.2 two-parameter shape)")
    func threeArgumentRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testThreeArgs() {
                let a = 1
                let b = 2
                let c = 3
                XCTAssertEqual(merge(a, b, c), merge(b, a, c))
            }
        }
        """
        // Per the M2 plan's open decision #6 default: literal reversal
        // of TWO arguments only. Three-or-more is out of scope for the
        // commutativity template.
        #expect(detect(in: source).isEmpty)
    }
}
