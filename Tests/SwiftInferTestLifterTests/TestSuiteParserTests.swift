import Testing
@testable import SwiftInferTestLifter

@Suite("TestSuiteParser — XCTest + Swift Testing recognition (M1.1)")
struct TestSuiteParserTests {

    // MARK: - XCTest recognition

    @Test("XCTestCase subclass with two test methods emits two xctest summaries")
    func xctestSubclassTwoMethods() {
        let source = """
        import XCTest

        final class FooTests: XCTestCase {
            func testAlpha() {
                XCTAssertEqual(1, 1)
            }
            func testBeta() {
                XCTAssertEqual(2, 2)
            }
        }
        """
        let summaries = TestSuiteParser.scan(source: source, file: "FooTests.swift")
        #expect(summaries.count == 2)
        #expect(summaries[0].harness == .xctest)
        #expect(summaries[0].className == "FooTests")
        #expect(summaries[0].methodName == "testAlpha")
        #expect(summaries[1].methodName == "testBeta")
    }

    @Test("XCTestCase setUp / tearDown / helper methods are not surfaced")
    func xctestSubclassSkipsHelpers() {
        let source = """
        import XCTest

        final class FooTests: XCTestCase {
            override func setUp() { super.setUp() }
            override func tearDown() { super.tearDown() }
            func helper() -> Int { 42 }
            func testReal() {
                XCTAssertEqual(helper(), 42)
            }
        }
        """
        let summaries = TestSuiteParser.scan(source: source, file: "FooTests.swift")
        #expect(summaries.count == 1)
        #expect(summaries[0].methodName == "testReal")
    }

    @Test("Method named test* in a struct (no XCTestCase inheritance) is not surfaced")
    func nonXCTestStructIsIgnored() {
        let source = """
        struct NotATest {
            func testNothing() {
                // Looks like a test but the enclosing type isn't XCTestCase.
            }
        }
        """
        let summaries = TestSuiteParser.scan(source: source, file: "NotATest.swift")
        #expect(summaries.isEmpty)
    }

    @Test("XCTestCase subclass without `final` is still recognized")
    func nonFinalXCTestCase() {
        let source = """
        import XCTest

        class FooTests: XCTestCase {
            func testThing() {
                XCTAssertTrue(true)
            }
        }
        """
        let summaries = TestSuiteParser.scan(source: source, file: "FooTests.swift")
        #expect(summaries.count == 1)
        #expect(summaries[0].harness == .xctest)
    }

    // MARK: - Swift Testing recognition

    @Test("@Test func at file scope emits a swiftTesting summary with nil className")
    func swiftTestingFileScope() {
        let source = """
        import Testing

        @Test func roundTripIsAnInverse() {
            #expect(decode(encode(42)) == 42)
        }
        """
        let summaries = TestSuiteParser.scan(source: source, file: "FooTests.swift")
        #expect(summaries.count == 1)
        #expect(summaries[0].harness == .swiftTesting)
        #expect(summaries[0].className == nil)
        #expect(summaries[0].methodName == "roundTripIsAnInverse")
    }

    @Test("@Test func inside a struct surfaces with the struct as className")
    func swiftTestingInsideStruct() {
        let source = """
        import Testing

        @Suite("Foo tests")
        struct FooTests {
            @Test func roundTripIsAnInverse() {
                #expect(decode(encode(42)) == 42)
            }
        }
        """
        let summaries = TestSuiteParser.scan(source: source, file: "FooTests.swift")
        #expect(summaries.count == 1)
        #expect(summaries[0].harness == .swiftTesting)
        #expect(summaries[0].className == "FooTests")
        #expect(summaries[0].methodName == "roundTripIsAnInverse")
    }

    @Test("@Test func inside a class (non-XCTestCase) surfaces as swiftTesting, not xctest")
    func swiftTestingInsideClass() {
        let source = """
        import Testing

        final class FooTests {
            @Test func testActuallyAnnotated() {
                #expect(true)
            }
        }
        """
        let summaries = TestSuiteParser.scan(source: source, file: "FooTests.swift")
        #expect(summaries.count == 1)
        #expect(summaries[0].harness == .swiftTesting)
    }

    @Test("@Test func with arguments and parameter list still surfaces")
    func swiftTestingParameterized() {
        let source = """
        import Testing

        struct FooTests {
            @Test(arguments: [1, 2, 3])
            func parametricCheck(_ value: Int) {
                #expect(value > 0)
            }
        }
        """
        let summaries = TestSuiteParser.scan(source: source, file: "FooTests.swift")
        #expect(summaries.count == 1)
        #expect(summaries[0].methodName == "parametricCheck")
    }

    // MARK: - Mixed corpora

    @Test("File mixing XCTest + Swift Testing emits both flavours")
    func mixedHarnessesInOneFile() {
        let source = """
        import XCTest
        import Testing

        final class LegacyFooTests: XCTestCase {
            func testOldStyle() {
                XCTAssertEqual(1, 1)
            }
        }

        @Suite("New tests")
        struct NewFooTests {
            @Test func newStyle() {
                #expect(true)
            }
        }
        """
        let summaries = TestSuiteParser.scan(source: source, file: "FooTests.swift")
        #expect(summaries.count == 2)
        // scan returns in source order — XCTest class appears first.
        #expect(summaries[0].harness == .xctest)
        #expect(summaries[1].harness == .swiftTesting)
    }

    // MARK: - Body preservation

    @Test("Body retains the function's CodeBlock for the slicer to walk")
    func bodyPreservesCodeBlock() {
        let source = """
        import XCTest

        final class FooTests: XCTestCase {
            func testRoundTrip() {
                let original = 42
                let encoded = encode(original)
                let decoded = decode(encoded)
                XCTAssertEqual(original, decoded)
            }
        }
        """
        let summaries = TestSuiteParser.scan(source: source, file: "FooTests.swift")
        #expect(summaries.count == 1)
        let body = summaries[0].body
        // The body's statements include the three `let` decls + the
        // assertion. The slicer (M1.2) consumes this directly.
        let statementCount = body.statements.count
        #expect(statementCount == 4)
    }

    // MARK: - Location

    @Test("Source location records the func keyword line")
    func sourceLocationOnFuncKeyword() {
        let source = """
        import XCTest

        final class FooTests: XCTestCase {
            func testThing() {
                XCTAssertTrue(true)
            }
        }
        """
        let summaries = TestSuiteParser.scan(source: source, file: "FooTests.swift")
        #expect(summaries.count == 1)
        #expect(summaries[0].location.file == "FooTests.swift")
        // `func testThing()` starts on line 4 of the source.
        #expect(summaries[0].location.line == 4)
    }

    // MARK: - Negative cases

    @Test("Empty file returns no summaries")
    func emptyFile() {
        let summaries = TestSuiteParser.scan(source: "", file: "Empty.swift")
        #expect(summaries.isEmpty)
    }

    @Test("Production-style class without test methods returns nothing")
    func productionClassReturnsNothing() {
        let source = """
        struct MyData {
            let value: Int
            func transformed() -> MyData { self }
        }
        """
        let summaries = TestSuiteParser.scan(source: source, file: "MyData.swift")
        #expect(summaries.isEmpty)
    }

    @Test("Function decl without a body (protocol requirement) is skipped")
    func protocolRequirementSkipped() {
        let source = """
        protocol Worker {
            func testWork()
        }
        """
        let summaries = TestSuiteParser.scan(source: source, file: "Worker.swift")
        #expect(summaries.isEmpty)
    }
}
