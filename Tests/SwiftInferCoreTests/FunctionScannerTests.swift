import Foundation
@testable import SwiftInferCore
import Testing

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

    // MARK: V1.57.A (cycle 54) + cycle-148 (Lever A) — non-public / SPI filter

    @Test("access-level filter: public + default-internal kept; explicit internal/private/fileprivate skipped (cycle 148)")
    func nonPublicAccessLevelsAreSkipped() {
        let source = """
        public func publicFn() {}
        private func privateFn() {}
        fileprivate func fileprivateFn() {}
        internal func internalFn() {}
        func defaultFn() {}
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        let names = summaries.map(\.name)
        #expect(names.contains("publicFn"))
        // Cycle 148: internal-BY-DEFAULT (no modifier token) is KEPT — this is
        // the normal shape of our internal test fixtures, which must stay
        // discoverable.
        #expect(names.contains("defaultFn"))
        // Cycle 148: EXPLICIT `internal` is now skipped (externally
        // unverifiable SPI; safe because default-internal carries no token).
        #expect(names.contains("internalFn") == false)
        #expect(names.contains("privateFn") == false)
        #expect(names.contains("fileprivateFn") == false)
        #expect(summaries.count == 2)   // publicFn + defaultFn
    }

    @Test("cycle 148: access modifier (not the `_` prefix) decides — public `_relaxedAdd`-style SPI is KEPT, explicit-internal is dropped")
    func underscoreNamedPublicSPIIsKept() {
        // The reliable signal is access level: swift-numerics ships
        // `public static func _relaxedAdd` (underscore-named but PUBLIC, and
        // it genuinely verifies → measured), while swift-collections'
        // `internal mutating func _ensureUnique` is real internal SPI. A
        // `_`-name filter would wrongly drop the former.
        let source = """
        public func _relaxedAdd() {}
        internal func _ensureUnique() {}
        func _defaultInternalHelper() {}
        """
        let names = FunctionScanner.scan(source: source, file: "Test.swift").map(\.name)
        #expect(names.contains("_relaxedAdd"))            // public SPI — kept
        #expect(names.contains("_defaultInternalHelper")) // default-internal — kept (fixture shape)
        #expect(names.contains("_ensureUnique") == false) // explicit internal — dropped
    }

    @Test("cycle 148: functions in a `_`-prefixed enclosing type / extension are skipped")
    func underscoreEnclosingTypesAreSkipped() {
        let source = """
        public struct Keep { public func ok() {} }
        public struct _HashTable { public func wordCount() {} }
        extension _UnsafeHashTable { public func word() {} }
        """
        let names = FunctionScanner.scan(source: source, file: "Test.swift").map(\.name)
        #expect(names.contains("ok"))
        #expect(names.contains("wordCount") == false)
        #expect(names.contains("word") == false)
    }
}
