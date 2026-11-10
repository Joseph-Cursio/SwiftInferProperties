@testable import SwiftInferTestLifter
import SwiftSyntax
import Testing

@Suite("Slicer — anchor + assertion recognition (M1.2)")
struct SlicerAnchorTests {

    @Test("Body with no assertion returns empty slice and never throws")
    func bodyWithNoAssertionEmptySlice() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testSetupOnly() {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        #expect(slice.assertion == nil)
        #expect(slice.propertyRegion.isEmpty)
        #expect(slice.setup.count == 2)
        #expect(slice.parameterizedValues.isEmpty)
    }

    @Test("Empty body returns empty slice")
    func emptyBody() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testNothing() { }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        #expect(slice.assertion == nil)
        #expect(slice.setup.isEmpty)
        #expect(slice.propertyRegion.isEmpty)
    }

    @Test("XCTAssertEqual is recognized as the anchor")
    func anchorXCTAssertEqual() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testSimple() {
                XCTAssertEqual(1, 1)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        #expect(slice.assertion?.kind == .xctAssertEqual)
        #expect(slice.assertion?.arguments.count == 2)
        #expect(slice.propertyRegion.count == 1)
    }

    @Test("XCTAssertTrue is recognized")
    func anchorXCTAssertTrue() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testTrue() {
                XCTAssertTrue(2 > 1)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        #expect(slice.assertion?.kind == .xctAssertTrue)
    }

    @Test("XCTAssertNotNil is recognized")
    func anchorXCTAssertNotNil() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testNotNil() {
                XCTAssertNotNil(Optional(42))
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        #expect(slice.assertion?.kind == .xctAssertNotNil)
    }

    @Test("#expect macro is recognized")
    func anchorExpectMacro() {
        let source = """
        import Testing
        @Test func swiftTestingExpect() {
            #expect(1 + 1 == 2)
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        #expect(slice.assertion?.kind == .expectMacro)
    }

    @Test("#require macro inside try wrapper is not yet anchored on (M2 follow-up)")
    func anchorRequireMacroBareNotTryWrapped() {
        // The slicer's anchor walk only matches a bare
        // MacroExpansionExpr. `try #require(...)` wraps the macro in a
        // TryExprSyntax — M1 documents the limit; M2+ may extend.
        let source = """
        import Testing
        @Test func swiftTestingRequire() throws {
            try #require(true)
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        #expect(slice.assertion == nil)
    }

    @Test("Multiple assertions: anchor binds to the terminal one")
    func multipleAssertionsAnchorsTerminal() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testTwo() {
                XCTAssertEqual(1, 1)
                XCTAssertTrue(true)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        #expect(slice.assertion?.kind == .xctAssertTrue)
    }

    @Test("Function call that isn't an assertion isn't anchored on")
    func unrelatedCallNotAnchored() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testRunsHelper() {
                someHelper()
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        #expect(slice.assertion == nil)
        #expect(slice.propertyRegion.isEmpty)
    }
}
