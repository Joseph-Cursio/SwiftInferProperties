@testable import SwiftInferTestLifter
import Testing

/// TestLifter M11.0 — `XCTAssertFalse` first-class recognition. Per M11
/// plan OD #2, the slicer routes `XCTAssertFalse` to the new
/// `.xctAssertFalse` `AssertionInvocation.Kind` case so the M11.1
/// `PredicateEquivalenceClassDetector` can homogeneity-check polarity
/// without parsing `XCTAssert(!predicate(x))` via expression-shape.
@Suite("Slicer — XCTAssertFalse recognition (M11.0)")
struct SlicerXCTAssertFalseTests {

    @Test("XCTAssertFalse is recognized as .xctAssertFalse")
    func anchorXCTAssertFalse() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testFalse() {
                XCTAssertFalse(1 > 2)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        #expect(slice.assertion?.kind == .xctAssertFalse)
        #expect(slice.assertion?.arguments.count == 1)
    }

    @Test("XCTAssertFalse over a predicate call surfaces the call as the assertion arg")
    func anchorXCTAssertFalseWithPredicateCall() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testInvalid_email() {
                XCTAssertFalse(isValid("a@"))
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        #expect(slice.assertion?.kind == .xctAssertFalse)
        #expect(slice.assertion?.arguments.count == 1)
    }

    @Test("XCTAssertFalse and XCTAssertTrue are distinct kinds")
    func falseAndTrueAreDistinct() {
        #expect(AssertionInvocation.Kind.xctAssertFalse
                != AssertionInvocation.Kind.xctAssertTrue)
    }
}
