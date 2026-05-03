import SwiftSyntax
import Testing
@testable import SwiftInferTestLifter

/// Shared body-slicing helper. Tests construct minimal one-method
/// classes / @Test funcs and slice the body of the first test method
/// the parser surfaces.
enum SlicerTestHelper {
    static func sliceFirstBody(in source: String) -> SlicedTestBody {
        let summaries = TestSuiteParser.scan(source: source, file: "T.swift")
        guard let first = summaries.first else {
            return SlicedTestBody.emptySlice(setup: [])
        }
        return Slicer.slice(first.body)
    }
}

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

@Suite("Slicer — backward slice + parameterized values (M1.2)")
struct SlicerBackwardSliceTests {

    @Test("Round-trip body pulls all four contributing stmts into property region")
    func roundTripPullsContributing() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testRoundTrip() {
                let original = MyData(value: 42)
                let encoded = encoder.encode(original)
                let decoded = decoder.decode(encoded)
                XCTAssertEqual(original, decoded)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        #expect(slice.propertyRegion.count == 4)
        #expect(slice.setup.isEmpty)
    }

    @Test("Mutating assignment falls through to setup")
    func mutatingAssignmentInSetup() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testWithMutation() {
                let original = 42
                encoder.outputFormatting = .pretty
                let encoded = encode(original)
                XCTAssertEqual(decode(encoded), original)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        #expect(slice.propertyRegion.count == 3)
        #expect(slice.setup.count == 1)
    }

    @Test("Bindings unrelated to the assertion fall through to setup")
    func unrelatedBindingsInSetup() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testWithSetup() {
                let unused = 99
                let original = 42
                let encoded = encode(original)
                XCTAssertEqual(decode(encoded), original)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        #expect(slice.setup.count == 1)
        #expect(slice.propertyRegion.count == 3)
    }

    @Test("Transitive backward-slice: encoder gets pulled in via encoded")
    func transitivelyPullsConfigBindings() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testTransitive() {
                let encoder = JSONEncoder()
                let original = 42
                let encoded = encoder.encode(original)
                XCTAssertEqual(decode(encoded), original)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        // Conservative inclusion documented in Slicer.swift's docstring:
        // encoded references encoder, so encoder gets pulled in even
        // though its initializer is config-y.
        #expect(slice.propertyRegion.count == 4)
        #expect(slice.setup.isEmpty)
    }

    @Test("Integer literal binding surfaces as parameterized value")
    func integerLiteralBinding() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testIntLiteral() {
                let original = 42
                XCTAssertEqual(decode(encode(original)), original)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        #expect(slice.parameterizedValues.count == 1)
        #expect(slice.parameterizedValues.first?.bindingName == "original")
        #expect(slice.parameterizedValues.first?.kind == .integer)
        #expect(slice.parameterizedValues.first?.literalText == "42")
    }

    @Test("String literal binding surfaces with .string kind")
    func stringLiteralBinding() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testStringLiteral() {
                let name = "alpha"
                XCTAssertEqual(decode(encode(name)), name)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        #expect(slice.parameterizedValues.first?.kind == .string)
    }

    @Test("Float literal in slice surfaces with .float kind")
    func floatLiteralBinding() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testFloat() {
                let pi = 3.14
                XCTAssertEqual(decode(encode(pi)), pi)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        #expect(slice.parameterizedValues.first?.kind == .float)
    }

    @Test("Non-literal initializer doesn't surface as parameterized")
    func nonLiteralInitializer() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testCall() {
                let original = MyData(value: 42)
                XCTAssertEqual(decode(encode(original)), original)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        #expect(slice.parameterizedValues.isEmpty)
    }

    @Test("Slicer never throws on weird shapes — top-level expression statements")
    func bizarreShapesDoNotThrow() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testWeirdness() {
                42
                "string"
                someFunction(with: things)
                let x = 1
                if x > 0 { print("positive") }
                XCTAssertEqual(x, 1)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        #expect(slice.assertion?.kind == .xctAssertEqual)
    }

    @Test("setup ∪ propertyRegion equals the original body in count")
    func setupAndPropertyCoverWholeBody() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testCover() {
                let a = 1
                let b = 2
                let c = a + b
                XCTAssertEqual(c, 3)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        #expect(slice.setup.count + slice.propertyRegion.count == 4)
    }
}
