import Testing
@testable import SwiftInferTestLifter

@Suite("SetupRegionTypeAnnotationScanner (TestLifter M4.0)")
struct SetupRegionTypeAnnotationScannerTests {

    @Test("Typed binding `let a: Doc = makeDoc()` recovers a → Doc")
    func typedBindingRecovers() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testTyped() {
                let a: Doc = makeDoc()
                XCTAssertNotNil(a)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        let map = SetupRegionTypeAnnotationScanner.annotations(in: slice)
        #expect(map["a"] == "Doc")
    }

    @Test("Bare-constructor binding `let a = Doc(title: \"x\")` recovers a → Doc")
    func bareConstructorRecovers() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testBare() {
                let a = Doc(title: "x")
                XCTAssertNotNil(a)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        let map = SetupRegionTypeAnnotationScanner.annotations(in: slice)
        #expect(map["a"] == "Doc")
    }

    @Test("Two-binding test method recovers both entries")
    func twoBindingsRecoverBoth() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testTwo() {
                let a = Doc(title: "x")
                let b: Author = makeAuthor()
                XCTAssertEqual(a.author, b)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        let map = SetupRegionTypeAnnotationScanner.annotations(in: slice)
        #expect(map["a"] == "Doc")
        #expect(map["b"] == "Author")
    }

    @Test("Non-constructor function call `let a = makeDoc()` does NOT recover")
    func functionCallNotRecovered() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testFnCall() {
                let a = makeDoc()
                XCTAssertNotNil(a)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        let map = SetupRegionTypeAnnotationScanner.annotations(in: slice)
        #expect(map["a"] == nil)
    }

    @Test("Tuple-pattern binding `let (a, b) = (Doc(), Author())` is silently skipped")
    func tuplePatternSkipped() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testTuple() {
                let (a, b) = (Doc(), Author())
                XCTAssertNotNil(a)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        let map = SetupRegionTypeAnnotationScanner.annotations(in: slice)
        #expect(map["a"] == nil)
        #expect(map["b"] == nil)
        #expect(map.isEmpty)
    }

    @Test("Type annotation wins when both annotation + bare-constructor would apply")
    func annotationWinsOverConstructor() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testBoth() {
                let a: SpecialDoc = Doc(title: "x")
                XCTAssertNotNil(a)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        let map = SetupRegionTypeAnnotationScanner.annotations(in: slice)
        #expect(map["a"] == "SpecialDoc")
    }

    @Test("Method-chain initializer `let a = makeDoc().normalize()` does NOT recover")
    func methodChainNotRecovered() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testChain() {
                let a = makeDoc().normalize()
                XCTAssertNotNil(a)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        let map = SetupRegionTypeAnnotationScanner.annotations(in: slice)
        #expect(map["a"] == nil)
    }

    @Test("Bindings recovered from both setup and property regions")
    func bothRegionsScanned() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testBothRegions() {
                let setupOnly: Doc = makeDoc()
                _ = setupOnly
                let inSlice: Author = makeAuthor()
                XCTAssertNotNil(inSlice)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        let map = SetupRegionTypeAnnotationScanner.annotations(in: slice)
        #expect(map["setupOnly"] == "Doc")
        #expect(map["inSlice"] == "Author")
    }

    @Test("Lowercase-prefixed identifier `let a = doc()` is treated as a function, not a type")
    func lowercaseIdentifierNotType() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testLowercase() {
                let a = doc()
                XCTAssertNotNil(a)
            }
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        let map = SetupRegionTypeAnnotationScanner.annotations(in: slice)
        #expect(map["a"] == nil)
    }

    @Test("Empty body produces empty map")
    func emptyBodyEmptyMap() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testEmpty() {}
        }
        """
        let slice = SlicerTestHelper.sliceFirstBody(in: source)
        let map = SetupRegionTypeAnnotationScanner.annotations(in: slice)
        #expect(map.isEmpty)
    }
}
