import Foundation
import Testing
@testable import SwiftInferCore

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
