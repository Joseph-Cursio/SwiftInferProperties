@testable import SwiftInferTestLifter
import Testing

/// The test-side route into the differential / oracle family.
///
/// TestLifter had six detectors and every one was keyed to a template the
/// catalog already shipped, so it corroborated laws it already knew and saw
/// nothing else. `mySort(x) == x.sorted()` was the canonical miss: a human had
/// already identified the invariant, decided it holds for all inputs, and
/// written it executably — better evidence than any naming heuristic — and the
/// tool discarded it because no template named the shape.
///
/// Two things had to land for this to work, and both are pinned here: a
/// template to promote into (`differential-equivalence`), and a slicer that
/// looks inside the repetition loop the law is quantified by.
@Suite("AssertReferenceEquivalenceDetector — subject vs reference computation")
struct AssertReferenceEquivalenceDetectorTests {

    private static func detect(in source: String) -> [DetectedReferenceEquivalence] {
        AssertReferenceEquivalenceDetector.detect(in: SlicerTestHelper.sliceFirstBody(in: source))
    }

    // MARK: - The shape

    @Test("inline: `mySort(input) == input.sorted()`")
    func inlineForm() throws {
        let detections = Self.detect(in: """
        import XCTest
        final class T: XCTestCase {
            func testSortMatchesReference() {
                let input = [3, 1, 2]
                XCTAssertEqual(mySort(input), input.sorted())
            }
        }
        """)
        let detection = try #require(detections.first)
        #expect(detection.subjectCallee == "mySort")
        #expect(detection.referenceCallee == "sorted")
        #expect(detection.sharedInput == "input")
        // Structural, not source order: one side is a method on the input.
        #expect(detection.directionIsCertain)
    }

    @Test("via bindings: the two computations are named first")
    func bindingForm() throws {
        let detections = Self.detect(in: """
        import XCTest
        final class T: XCTestCase {
            func testSortMatchesReference() {
                let input = [3, 1, 2]
                let mine = mySort(input)
                let reference = input.sorted()
                XCTAssertEqual(mine, reference)
            }
        }
        """)
        let detection = try #require(detections.first)
        #expect(detection.subjectCallee == "mySort")
        #expect(detection.referenceCallee == "sorted")
    }

    @Test("THE quote's shape: a random-driven loop is the quantifier")
    func randomDrivenLoop() throws {
        // The `.random(in:)` invariant test. Before the slicer learned to look
        // inside a lone repetition loop this scored nothing, with no other
        // difference from the inline form — measured, not assumed.
        let detections = Self.detect(in: """
        import XCTest
        final class T: XCTestCase {
            func testSortIsCorrectOnRandomArrays() {
                for _ in 0..<10_000 {
                    let input = (0..<50).map { _ in Int.random(in: -1000...1000) }
                    XCTAssertEqual(mySort(input), input.sorted())
                }
            }
        }
        """)
        let detection = try #require(detections.first)
        #expect(detection.subjectCallee == "mySort")
        #expect(detection.referenceCallee == "sorted")
    }

    @Test("Swift Testing's `#expect(a == b)` form")
    func expectMacroForm() throws {
        let detections = Self.detect(in: """
        import Testing
        struct T {
            @Test func sortMatchesReference() {
                let input = [3, 1, 2]
                #expect(mySort(input) == input.sorted())
            }
        }
        """)
        #expect(try #require(detections.first).subjectCallee == "mySort")
    }

    // MARK: - Told apart from the other five detectors

    @Test("a round-trip is not a reference equivalence — one side is the bare input")
    func roundTripNotClaimed() {
        #expect(Self.detect(in: """
        import XCTest
        final class T: XCTestCase {
            func testRoundTrip() {
                let value = "x"
                XCTAssertEqual(decode(encode(value)), value)
            }
        }
        """).isEmpty)
    }

    @Test("a double-apply is not a reference equivalence — same callee both sides")
    func idempotenceNotClaimed() {
        #expect(Self.detect(in: """
        import XCTest
        final class T: XCTestCase {
            func testIdempotent() {
                let s = "x"
                XCTAssertEqual(normalize(normalize(s)), normalize(s))
            }
        }
        """).isEmpty)
    }

    @Test("two unrelated values are an example, not a law")
    func unsharedInputNotClaimed() {
        // `f(a) == g(b)` with no shared identifier is a fixture assertion. The
        // shared input is what makes it a comparison of two computations over
        // ONE value.
        #expect(Self.detect(in: """
        import XCTest
        final class T: XCTestCase {
            func testUnrelated() {
                let a = [1]
                let b = [2]
                XCTAssertEqual(mySort(a), reference(b))
            }
        }
        """).isEmpty)
    }

    @Test("when neither side is a method on the input, the direction is flagged uncertain")
    func uncertainDirectionIsFlagged() throws {
        let detections = Self.detect(in: """
        import XCTest
        final class T: XCTestCase {
            func testTwoImplementations() {
                let input = [3, 1, 2]
                XCTAssertEqual(mySort(input), referenceSort(input))
            }
        }
        """)
        let detection = try #require(detections.first)
        // Both sides take the input as an argument, so subject/reference falls
        // back to source order — and the rendered line must say so, because a
        // counterexample is attributed to the subject.
        #expect(!detection.directionIsCertain)
    }

    @Test("a CONSTRUCTED EXPECTED VALUE is not an oracle — swift-foundation")
    func constructedExpectationRejected() {
        // Measured on the real swift-foundation suite, where this was the
        // detector's ONLY firing and it was false:
        //
        //     #expect(originalAttributes.merging(overlapping, mergePolicy: .keepCurrent)
        //             == originalAttributes.testDouble(4.3))
        //
        // Both sides are methods on the same receiver, so the shared-input test
        // passes. But `testDouble` is an AttributedString ATTRIBUTE KEY and the
        // right-hand side is the expected container being BUILT. The literal
        // `4.3` is the tell.
        #expect(Self.detect(in: """
        import Testing
        struct T {
            @Test func merge() {
                let originalAttributes = container()
                #expect(originalAttributes.merging(overlapping) == originalAttributes.testDouble(4.3))
            }
        }
        """).isEmpty)
    }

    @Test("a reference that consumes the shared input still counts — swift-foundation")
    func genuineReferenceSurvives() throws {
        // The true positive from the same suite: a fast lookup checked against
        // a reference set. Both sides consume `c`; neither carries a literal.
        let detections = Self.detect(in: """
        import Testing
        struct T {
            @Test func allowed() {
                let c = codeUnit
                #expect(isAllowedCodeUnit(c) == allowedSet.contains(c))
            }
        }
        """)
        #expect(try #require(detections.first).subjectCallee == "isAllowedCodeUnit")
    }

    @Test("setup line THEN a loop is unwrapped — the shape real tests actually have")
    func setupThenLoopIsUnwrapped() throws {
        // The first cut required the loop to be the body's ONLY statement, and
        // fired on ZERO of the ten random-driven tests in swift-foundation.
        // Real property-style tests set up a generator first — this is
        // UUIDTests.randomVersionAndVariant's shape.
        let detections = Self.detect(in: """
        import Testing
        struct T {
            @Test func sortMatchesReference() {
                var generator = SystemRandomNumberGenerator()
                for _ in 0..<10000 {
                    let input = randomArray(using: &generator)
                    #expect(mySort(input) == input.sorted())
                }
            }
        }
        """)
        #expect(try #require(detections.first).subjectCallee == "mySort")
    }

    @Test("a body that DOES WORK before looping is not reinterpreted")
    func nonBindingPrefixBlocksUnwrap() {
        // Only leading bindings are tolerated. A body that calls, mutates, or
        // asserts before looping is not a quantifier over just its tail.
        let slice = SlicerTestHelper.sliceFirstBody(in: """
        import XCTest
        final class T: XCTestCase {
            func testMixed() {
                XCTAssertEqual(setUpThing(), 1)
                for _ in 0..<10 {
                    let input = [3, 1, 2]
                    XCTAssertEqual(mySort(input), input.sorted())
                }
            }
        }
        """)
        // The top-level assertion stays the anchor, so the loop's inner
        // comparison is never surfaced.
        #expect(AssertReferenceEquivalenceDetector.detect(in: slice).isEmpty)
    }

    // MARK: - The slicer change, scoped

    @Test("a loop is unwrapped only when it is the WHOLE body")
    func unwrapIsNarrow() {
        let single = SlicerTestHelper.sliceFirstBody(in: """
        import XCTest
        final class T: XCTestCase {
            func testLoopOnly() {
                for _ in 0..<10 {
                    let input = [3, 1, 2]
                    XCTAssertEqual(mySort(input), input.sorted())
                }
            }
        }
        """)
        #expect(single.assertion != nil, "a lone repetition loop is the quantifier")

        // A loop that merely BUILDS a fixture before a later assertion must be
        // left alone — the top-level assertion is still the right anchor.
        let fixtureLoop = SlicerTestHelper.sliceFirstBody(in: """
        import XCTest
        final class T: XCTestCase {
            func testFixtureBuiltInLoop() {
                var items: [Int] = []
                for i in 0..<10 {
                    items.append(i)
                }
                XCTAssertEqual(mySort(items), items.sorted())
            }
        }
        """)
        #expect(fixtureLoop.assertion != nil)
        #expect(!AssertReferenceEquivalenceDetector.detect(in: fixtureLoop).isEmpty)
    }
}
