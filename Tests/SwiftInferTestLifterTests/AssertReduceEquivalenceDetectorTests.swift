import Testing
@testable import SwiftInferTestLifter

private func detectReduceEquivalence(in source: String) -> [DetectedReduceEquivalence] {
    let slice = SlicerTestHelper.sliceFirstBody(in: source)
    return AssertReduceEquivalenceDetector.detect(in: slice)
}

@Suite("AssertReduceEquivalenceDetector — collapsed shape (M5.3)")
struct ReduceEquivalenceCollapsedTests {

    @Test("Per-shape (i): collapsed XCTAssertEqual with operator op (+) is detected")
    func collapsedXCTestOperatorOp() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testSumReduceIsAssociative() {
                let xs = [1, 2, 3, 4]
                XCTAssertEqual(xs.reduce(0, +), xs.reversed().reduce(0, +))
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.count == 1)
        let detected = detections.first
        #expect(detected?.opCalleeName == "+")
        #expect(detected?.seedSource == "0")
        #expect(detected?.collectionBindingName == "xs")
    }

    @Test("Per-shape (ii): collapsed #expect with named-function op (combine) is detected")
    func collapsedSwiftTestingNamedOp() {
        let source = """
        import Testing
        struct T {
            @Test
            func combineIsAssociative() {
                let items = [1, 2, 3]
                #expect(items.reduce(.zero, combine) == items.reversed().reduce(.zero, combine))
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.count == 1)
        let detected = detections.first
        #expect(detected?.opCalleeName == "combine")
        #expect(detected?.seedSource == ".zero")
        #expect(detected?.collectionBindingName == "items")
    }

    @Test("Reversed argument order (xs.reversed() on lhs, direct on rhs) is detected")
    func collapsedReversedArgumentOrder() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testReversedFirst() {
                let xs = [1, 2, 3]
                XCTAssertEqual(xs.reversed().reduce(0, +), xs.reduce(0, +))
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.opCalleeName == "+")
    }

    @Test("Per-shape (iv): tautology with no .reversed() on either side is rejected")
    func tautologyNoReversedRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testTautology() {
                let xs = [1, 2, 3]
                XCTAssertEqual(xs.reduce(0, +), xs.reduce(0, +))
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Both-reversed shape (.reversed() on both sides) is rejected")
    func bothReversedRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testBothReversed() {
                let xs = [1, 2, 3]
                XCTAssertEqual(xs.reversed().reduce(0, +), xs.reversed().reduce(0, +))
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Per-shape (v): different ops (+, *) are rejected")
    func differentOpsRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testDifferentOps() {
                let xs = [1, 2, 3]
                XCTAssertEqual(xs.reduce(0, +), xs.reversed().reduce(0, *))
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Different seeds (0 vs 1) are rejected")
    func differentSeedsRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testDifferentSeeds() {
                let xs = [1, 2, 3]
                XCTAssertEqual(xs.reduce(0, +), xs.reversed().reduce(1, +))
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Different collection identifiers (xs vs ys) are rejected")
    func differentCollectionsRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testDifferentCollections() {
                let xs = [1, 2, 3]
                let ys = [4, 5, 6]
                XCTAssertEqual(xs.reduce(0, +), ys.reversed().reduce(0, +))
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Closure op (not a DeclRef) is rejected — closures deferred")
    func closureOpRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testClosureOp() {
                let xs = [1, 2, 3]
                XCTAssertEqual(
                    xs.reduce(0, { acc, x in acc + x }),
                    xs.reversed().reduce(0, { acc, x in acc + x })
                )
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Three-arg .reduce(into:_:_:)-shaped call (count != 2) is rejected")
    func threeArgReduceRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testThreeArg() {
                let xs = [1, 2, 3]
                XCTAssertEqual(xs.reduce(0, +, +), xs.reversed().reduce(0, +, +))
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }
}

@Suite("AssertReduceEquivalenceDetector — explicit shape (M5.3)")
struct ReduceEquivalenceExplicitTests {

    @Test("Per-shape (iii): explicit two-binding form is detected")
    func explicitTwoBinding() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testExplicitForm() {
                let xs = [1, 2, 3]
                let lhs = xs.reduce(0, +)
                let rhs = xs.reversed().reduce(0, +)
                XCTAssertEqual(lhs, rhs)
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.count == 1)
        let detected = detections.first
        #expect(detected?.opCalleeName == "+")
        #expect(detected?.seedSource == "0")
        #expect(detected?.collectionBindingName == "xs")
    }

    @Test("Explicit two-binding with named op (combine) is detected")
    func explicitNamedOp() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testExplicitCombine() {
                let items = [1, 2, 3]
                let lhs = items.reduce(.zero, combine)
                let rhs = items.reversed().reduce(.zero, combine)
                XCTAssertEqual(lhs, rhs)
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.opCalleeName == "combine")
        #expect(detections.first?.seedSource == ".zero")
    }

    @Test("Explicit form with reversed assertion order XCTAssertEqual(rhs, lhs) is detected")
    func explicitReversedAssertionOrder() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testExplicitReversed() {
                let xs = [1, 2, 3]
                let lhs = xs.reduce(0, +)
                let rhs = xs.reversed().reduce(0, +)
                XCTAssertEqual(rhs, lhs)
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.count == 1)
        #expect(detections.first?.opCalleeName == "+")
    }

    @Test("Explicit form rejects when binding initializer is not a reduce call")
    func explicitNonReduceBindingRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testNonReduceBinding() {
                let xs = [1, 2, 3]
                let lhs = xs.first ?? 0
                let rhs = xs.reversed().reduce(0, +)
                XCTAssertEqual(lhs, rhs)
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Explicit form rejects when both bindings are direct (no .reversed())")
    func explicitBothDirectRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testBothDirect() {
                let xs = [1, 2, 3]
                let lhs = xs.reduce(0, +)
                let rhs = xs.reduce(0, +)
                XCTAssertEqual(lhs, rhs)
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }

    @Test("Explicit form rejects when ops differ across bindings")
    func explicitDifferentOpsRejected() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testDifferentOps() {
                let xs = [1, 2, 3]
                let lhs = xs.reduce(0, +)
                let rhs = xs.reversed().reduce(0, *)
                XCTAssertEqual(lhs, rhs)
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
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
                let lhs = xs.reduce(0, +)
                let rhs = xs.reversed().reduce(0, +)
                #expect(lhs == rhs)
            }
        }
        """
        let detections = detectReduceEquivalence(in: source)
        #expect(detections.isEmpty)
    }
}

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
