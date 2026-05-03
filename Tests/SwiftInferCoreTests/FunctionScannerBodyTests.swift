import Foundation
import Testing
@testable import SwiftInferCore

@Suite("FunctionScanner — body signals and edge cases")
struct FunctionScannerBodyTests {

    // MARK: Body signals

    @Test
    func detectsNonDeterministicCallToDate() throws {
        let source = """
        func canonicalize() {
            let now = Date()
            _ = now
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.bodySignals.hasNonDeterministicCall)
        #expect(summary.bodySignals.nonDeterministicAPIsDetected == ["Date"])
    }

    @Test
    func detectsNonDeterministicCallToUUIDAndRandom() throws {
        let source = """
        func mix() -> Int {
            let id = UUID()
            _ = id
            return Int.random(in: 0..<10)
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.bodySignals.hasNonDeterministicCall)
        #expect(summary.bodySignals.nonDeterministicAPIsDetected.contains("UUID"))
        #expect(summary.bodySignals.nonDeterministicAPIsDetected.contains("Int.random"))
    }

    @Test
    func deterministicBodyHasNoSignals() throws {
        let source = "func double(_ x: Int) -> Int { return x * 2 }"
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.bodySignals == .empty)
    }

    @Test
    func detectsSelfComposition() throws {
        let source = """
        func normalize(_ s: String) -> String {
            return normalize(normalize(s))
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.bodySignals.hasSelfComposition)
    }

    @Test
    func nonSelfCompositionIsNotDetected() {
        let source = """
        func double(_ x: Int) -> Int {
            return triple(x)
        }
        func triple(_ x: Int) -> Int { return x * 3 }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        #expect(summaries.count == 2)
        #expect(summaries.allSatisfy { $0.bodySignals.hasSelfComposition == false })
    }

    // MARK: Reducer-op detection (M2.4)

    @Test
    func detectsBareFunctionReferenceAsReducerOp() throws {
        let source = """
        func driver(_ xs: [Int]) -> Int {
            return xs.reduce(0, add)
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.bodySignals.reducerOpsReferenced == ["add"])
    }

    @Test
    func detectsMemberAccessReferenceAsReducerOp() throws {
        let source = """
        func driver(_ xs: [Int]) -> Int {
            return xs.reduce(0, MyType.combine)
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.bodySignals.reducerOpsReferenced == ["combine"])
    }

    @Test
    func detectsReducerOpUnderReduceIntoForm() throws {
        // `.reduce(into:_:)` is the in-place variant; the closure-position
        // arg still resolves the candidate function reference.
        let source = """
        func driver(_ xs: [Int]) -> Int {
            return xs.reduce(into: 0, accumulate)
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.bodySignals.reducerOpsReferenced == ["accumulate"])
    }

    @Test
    func multipleDistinctReducerOpsAreSorted() throws {
        let source = """
        func driver(_ xs: [Int]) -> Int {
            let a = xs.reduce(0, zebra)
            let b = xs.reduce(0, alpha)
            return a + b
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.bodySignals.reducerOpsReferenced == ["alpha", "zebra"])
    }

    @Test
    func reducerOpDuplicatedAcrossCallsDeduplicates() throws {
        let source = """
        func driver(_ xs: [Int], _ ys: [Int]) -> Int {
            let a = xs.reduce(0, add)
            let b = ys.reduce(0, add)
            return a + b
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.bodySignals.reducerOpsReferenced == ["add"])
    }

    @Test
    func reduceWithClosureArgumentIsNotRecorded() throws {
        // M2.4 conservative scope — only named-function references resolve.
        // Closures and method refs with parameter labels are intentionally
        // skipped to avoid false positives.
        let source = """
        func driver(_ xs: [Int]) -> Int {
            return xs.reduce(0) { acc, x in acc + x }
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.bodySignals.reducerOpsReferenced.isEmpty)
    }

    @Test
    func reduceWithSingleArgumentIsNotRecorded() throws {
        // Pure trailing-closure form: no second positional argument.
        let source = """
        func driver(_ xs: [Int]) -> Int {
            return xs.reduce(0, { $0 + $1 })
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        // Closure literal isn't a function reference — no record.
        #expect(summary.bodySignals.reducerOpsReferenced.isEmpty)
    }

    @Test
    func nonReduceMemberCallDoesNotProduceReducerOp() throws {
        let source = """
        func driver(_ xs: [Int]) -> Int {
            return xs.map(double).first ?? 0
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.bodySignals.reducerOpsReferenced.isEmpty)
    }

    // MARK: Edge cases — multiple, empty, no functions

    @Test
    func multipleFunctionsReturnedInDeclarationOrder() {
        let source = """
        func first() {}
        func second() {}
        func third() {}
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        #expect(summaries.map(\.name) == ["first", "second", "third"])
    }

    @Test
    func emptySourceReturnsEmptyArray() {
        let summaries = FunctionScanner.scan(source: "", file: "Test.swift")
        #expect(summaries.isEmpty)
    }

    @Test
    func sourceWithNoFunctionsReturnsEmptyArray() {
        let source = """
        struct OnlyType {
            let value: Int = 0
        }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        #expect(summaries.isEmpty)
    }

    // MARK: Directory scan

    @Test
    func directoryScanFindsFunctionsInSortedFileOrder() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("FunctionScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let fileB = temp.appendingPathComponent("B.swift")
        let fileA = temp.appendingPathComponent("A.swift")
        try "func b() {}".write(to: fileB, atomically: true, encoding: .utf8)
        try "func a() {}".write(to: fileA, atomically: true, encoding: .utf8)

        let summaries = try FunctionScanner.scan(directory: temp)
        #expect(summaries.map(\.name) == ["a", "b"])
    }

    @Test
    func directoryScanIgnoresNonSwiftFiles() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("FunctionScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        try "func a() {}".write(
            to: temp.appendingPathComponent("A.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "// not swift".write(
            to: temp.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        let summaries = try FunctionScanner.scan(directory: temp)
        #expect(summaries.map(\.name) == ["a"])
    }
}
