import Foundation
import Testing
@testable import SwiftInferCore

// swiftlint:disable file_length
// Two cohesive scanner suites — splitting along the 400-line file limit
// would orphan related body-signal cases (non-determinism, self-comp,
// reducer-op refs) into a separate file for no reader benefit.

@Suite("FunctionScanner — header and structure")
struct FunctionScannerHeaderTests {

    // MARK: Header info

    @Test
    func parsesTopLevelFunctionHeader() throws {
        let source = """
        func normalize(_ s: String) -> String {
            return s
        }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        #expect(summaries.count == 1)

        let summary = try #require(summaries.first)
        #expect(summary.name == "normalize")
        #expect(summary.returnTypeText == "String")
        #expect(summary.isThrows == false)
        #expect(summary.isAsync == false)
        #expect(summary.isMutating == false)
        #expect(summary.isStatic == false)
        #expect(summary.containingTypeName == nil)

        #expect(summary.parameters.count == 1)
        let param = try #require(summary.parameters.first)
        #expect(param.label == nil)
        #expect(param.internalName == "s")
        #expect(param.typeText == "String")
        #expect(param.isInout == false)
    }

    @Test
    func detectsThrowsAndAsync() throws {
        let source = "func send() async throws -> Data { return Data() }"
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.isThrows)
        #expect(summary.isAsync)
        #expect(summary.returnTypeText == "Data")
    }

    @Test
    func detectsMutatingInStruct() throws {
        let source = """
        struct Counter {
            var value: Int = 0
            mutating func reset() { value = 0 }
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.name == "reset")
        #expect(summary.isMutating)
        #expect(summary.containingTypeName == "Counter")
    }

    @Test
    func detectsStaticInEnum() throws {
        let source = """
        enum Helpers {
            static func compute() -> Int { return 42 }
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.isStatic)
        #expect(summary.containingTypeName == "Helpers")
    }

    @Test
    func functionWithoutReturnClauseHasNilReturnType() throws {
        let source = "func sideEffect() { print(\"hi\") }"
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.returnTypeText == nil)
    }

    // MARK: Parameter label cases

    @Test
    func parameterLabelSuppressedByUnderscore() throws {
        let source = "func f(_ x: Int) {}"
        let param = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first?.parameters.first
        )
        #expect(param.label == nil)
        #expect(param.internalName == "x")
        #expect(param.typeText == "Int")
    }

    @Test
    func parameterWithCustomLabel() throws {
        let source = "func f(label name: Int) {}"
        let param = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first?.parameters.first
        )
        #expect(param.label == "label")
        #expect(param.internalName == "name")
    }

    @Test
    func parameterWithSingleNameUsesItForBothLabelAndName() throws {
        let source = "func f(value: Int) {}"
        let param = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first?.parameters.first
        )
        #expect(param.label == "value")
        #expect(param.internalName == "value")
    }

    @Test
    func detectsInoutParameter() throws {
        let source = "func f(value: inout Int) { value += 1 }"
        let param = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first?.parameters.first
        )
        #expect(param.isInout)
        #expect(param.typeText == "Int")
    }

    // MARK: Containing scope

    @Test
    func extensionContributesExtendedTypeName() throws {
        let source = """
        extension Array {
            func summarize() -> Int { return count }
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.containingTypeName == "Array")
    }

    @Test
    func nestedTypesUseInnermostName() throws {
        let source = """
        struct Outer {
            struct Inner {
                func bar() {}
            }
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.containingTypeName == "Inner")
    }

    @Test
    func actorIsRecognizedAsContainingType() throws {
        let source = """
        actor Counter {
            func tick() {}
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.containingTypeName == "Counter")
    }

    @Test
    func protocolRequirementsAreSkipped() {
        let source = """
        protocol P {
            func required() -> Int
        }
        func topLevel() {}
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        #expect(summaries.count == 1)
        #expect(summaries.first?.name == "topLevel")
    }

    // MARK: Source location

    @Test
    func sourceLocationReportsLineOfFuncKeyword() throws {
        let source = """
        // line 1
        // line 2
        func target() {}
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Sources/X.swift").first
        )
        #expect(summary.location.file == "Sources/X.swift")
        #expect(summary.location.line == 3)
    }
}

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
