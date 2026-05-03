import Foundation
import Testing
@testable import SwiftInferTestLifter

@Suite("SetupRegionConstructionScanner (TestLifter M4.1)")
struct SetupRegionConstructionScannerTests {

    // MARK: - Helper

    /// Parse `source` (one or more test methods) into TestMethodSummary
    /// records and run the scanner.
    private static func record(_ sources: [String]) -> ConstructionRecord {
        var methods: [TestMethodSummary] = []
        for (index, source) in sources.enumerated() {
            methods.append(contentsOf: TestSuiteParser.scan(
                source: source,
                file: "Test\(index).swift"
            ))
        }
        return SetupRegionConstructionScanner.record(over: methods)
    }

    // MARK: - Acceptance: aggregation

    @Test("Three sites with same shape aggregate to one entry with siteCount: 3")
    func aggregatesSameShape() {
        let file1 = """
        import XCTest
        final class A: XCTestCase {
            func testA() {
                let a = Doc(title: "x", count: 3)
                XCTAssertNotNil(a)
            }
        }
        """
        let file2 = """
        import XCTest
        final class B: XCTestCase {
            func testB() {
                let b = Doc(title: "y", count: 5)
                XCTAssertNotNil(b)
            }
        }
        """
        let file3 = """
        import XCTest
        final class C: XCTestCase {
            func testC() {
                let c = Doc(title: "z", count: 7)
                XCTAssertNotNil(c)
            }
        }
        """
        let record = Self.record([file1, file2, file3])
        let docEntries = record.entries(for: "Doc")
        #expect(docEntries.count == 1)
        let entry = try? #require(docEntries.first)
        #expect(entry?.siteCount == 3)
        #expect(entry?.observedLiterals.count == 3)
    }

    @Test("Same labels in different orderings collapse to one entry (label set, not list)")
    func labelOrderIndependent() {
        let file1 = """
        import XCTest
        final class A: XCTestCase {
            func testA() {
                let a = Doc(title: "x", count: 3)
                XCTAssertNotNil(a)
            }
        }
        """
        let file2 = """
        import XCTest
        final class B: XCTestCase {
            func testB() {
                let b = Doc(count: 5, title: "y")
                XCTAssertNotNil(b)
            }
        }
        """
        let record = Self.record([file1, file2])
        let docEntries = record.entries(for: "Doc")
        #expect(docEntries.count == 1)
        #expect(docEntries.first?.siteCount == 2)
    }

    @Test("Different label sets produce two distinct entries")
    func differentLabelSetsDistinct() {
        let file1 = """
        import XCTest
        final class A: XCTestCase {
            func testA() {
                let a = Doc(title: "x")
                XCTAssertNotNil(a)
            }
        }
        """
        let file2 = """
        import XCTest
        final class B: XCTestCase {
            func testB() {
                let b = Doc(title: "y", author: "z")
                XCTAssertNotNil(b)
            }
        }
        """
        let record = Self.record([file1, file2])
        let docEntries = record.entries(for: "Doc")
        #expect(docEntries.count == 2)
        // Both entries have siteCount: 1 (each shape observed once).
        #expect(docEntries.allSatisfy { $0.siteCount == 1 })
    }

    @Test("Constructor with non-literal arg is skipped — can't fingerprint opaque expressions")
    func nonLiteralArgsSkipped() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testNonLiteral() {
                let a = Doc(title: makeName(), count: 3)
                XCTAssertNotNil(a)
            }
        }
        """
        let record = Self.record([source])
        // The Doc(...) call has a non-literal `makeName()` arg, so the
        // entire call is skipped. No record entries for Doc.
        #expect(record.entries(for: "Doc").isEmpty)
    }

    @Test("Empty constructor `Doc()` produces an entry with empty argument list")
    func emptyConstructorRecorded() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testEmptyCtor() {
                let a = Doc()
                let b = Doc()
                let c = Doc()
                XCTAssertNotNil(a)
            }
        }
        """
        let record = Self.record([source])
        let docEntries = record.entries(for: "Doc")
        #expect(docEntries.count == 1)
        #expect(docEntries.first?.siteCount == 3)
        #expect(docEntries.first?.shape.arguments.isEmpty == true)
    }

    @Test("Lowercase-prefixed call `makeDoc()` is skipped — not a constructor")
    func lowercaseCallNotConstructor() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testFnCall() {
                let a = makeDoc()
                XCTAssertNotNil(a)
            }
        }
        """
        let record = Self.record([source])
        #expect(record.entries.isEmpty)
    }

    @Test("Method-chain `Doc().normalize()` records the inner Doc() construction")
    func methodChainOuterCallSkippedInnerRecorded() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testChain() {
                let a = Doc().normalize()
                XCTAssertNotNil(a)
            }
        }
        """
        let record = Self.record([source])
        // Doc() is recorded (matches the constructor shape); .normalize()
        // is a member-access call whose called expression is not a bare
        // type-shaped identifier, so it's skipped.
        let docEntries = record.entries(for: "Doc")
        #expect(docEntries.count == 1)
        #expect(docEntries.first?.siteCount == 1)
    }

    @Test("Mixed-kind args produce a stable fingerprint per kind combination")
    func kindCombinationFingerprint() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testMixed() {
                let a = Mix(s: "x", n: 1, f: 1.0, b: true)
                let c = Mix(s: "y", n: 2, f: 2.0, b: false)
                XCTAssertNotNil(a)
                XCTAssertNotNil(c)
            }
        }
        """
        let record = Self.record([source])
        let mixEntries = record.entries(for: "Mix")
        #expect(mixEntries.count == 1)
        #expect(mixEntries.first?.siteCount == 2)
        let kinds = mixEntries.first?.shape.arguments.map(\.kind) ?? []
        // Sort key ordering: boolean(0), float(1), integer(2), string(3).
        // Labels sort: b < f < n < s, which happens to match the kind
        // sort here — both orderings agree.
        #expect(kinds == [.boolean, .float, .integer, .string])
    }

    @Test("Visit walks nested calls — `XCTAssertEqual(Doc(), Doc())` records two Doc sites")
    func nestedConstructorsBothRecorded() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testNested() {
                XCTAssertEqual(Doc(), Doc())
            }
        }
        """
        let record = Self.record([source])
        let docEntries = record.entries(for: "Doc")
        #expect(docEntries.count == 1)
        #expect(docEntries.first?.siteCount == 2)
    }

    @Test("Empty input produces empty record")
    func emptyInputEmptyRecord() {
        let record = SetupRegionConstructionScanner.record(over: [])
        #expect(record.entries.isEmpty)
    }

    @Test("Entries are stably sorted by (typeName, shape) for deterministic output")
    func entriesStablySorted() {
        let source = """
        import XCTest
        final class T: XCTestCase {
            func testMulti() {
                let z = Zebra()
                let a = Apple(name: "x")
                let b = Banana(count: 1)
                XCTAssertNotNil(z)
            }
        }
        """
        let record = Self.record([source])
        let names = record.entries.map(\.typeName)
        #expect(names == ["Apple", "Banana", "Zebra"])
    }

    // MARK: - Acceptance: § 13 perf re-check

    @Test("Record building over 100 synthetic test files completes in < 250ms")
    func hundredFilePerf() throws {
        var allMethods: [TestMethodSummary] = []
        for index in 0..<100 {
            let source = """
            import XCTest
            final class T\(index): XCTestCase {
                func testRecord() {
                    let a = Doc(title: "x\(index)", count: \(index))
                    let b = Doc(title: "y\(index)", count: \(index + 1))
                    XCTAssertNotNil(a)
                    XCTAssertNotNil(b)
                }
            }
            """
            allMethods.append(contentsOf: TestSuiteParser.scan(
                source: source,
                file: "T\(index).swift"
            ))
        }
        let start = Date()
        let record = SetupRegionConstructionScanner.record(over: allMethods)
        let elapsed = Date().timeIntervalSince(start)
        // 250ms budget calibrated against parallel-test-load behavior:
        // in isolation the scanner pass over 200 methods takes ~70ms,
        // but parallel test execution (default `swift test` mode)
        // routinely doubles the wall-clock for visitor-heavy work.
        // 250ms gives ~2× headroom over the parallel-load baseline.
        // The §13 row-2 budget (TestLifter parse 100 files < 3s wall)
        // is the load-bearing perf check; this unit perf is a
        // sanity guard against algorithmic regression.
        #expect(elapsed < 0.25, "Record building took \(elapsed)s — over the M4.1 250ms unit-perf budget")
        // Sanity-check the record is non-trivial: 100 files × 2 Doc()
        // sites each = 200 sites, all sharing a shape.
        let docEntries = record.entries(for: "Doc")
        #expect(docEntries.count == 1)
        #expect(docEntries.first?.siteCount == 200)
    }
}
