import Foundation
import SwiftInferCore
import Testing

// Non-public / SPI scan-time filters (cycles 54 / 148 / 151). Split out of
// FunctionScannerTests.swift (cycle 151) to keep that struct under SwiftLint's
// type_body_length cap. Each filter removes a shape an external verifier can
// never call, so it shouldn't inflate the v1 algebraic measured denominator
// (PRD §3.5 — high precision, fewer suggestions).
@Suite("FunctionScanner — non-public / SPI filters")
struct FunctionScannerAccessFilterTests {

    // MARK: V1.57.A (cycle 54) + cycle-148 (Lever A)

    @Test("access filter: public + default-internal kept; explicit internal/private/fileprivate skipped (c148)")
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

    @Test("c148: access modifier (not `_` prefix) decides — public `_relaxedAdd` SPI kept, explicit-internal dropped")
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

    // MARK: cycle 151 (Lever D) — @_spi / nested-local / non-public-type

    @Test("c151: @_spi(...) declarations are skipped (e.g. OrderedSet+Testing capacity shims)")
    func spiDeclarationsAreSkipped() {
        let source = """
        public struct Box {
            @_spi(Testing) public static func _minimumCapacity(forScale s: Int) -> Int { s }
            public static func realAPI(_ x: Int) -> Int { x }
        }
        """
        let names = FunctionScanner.scan(source: source, file: "Test.swift").map(\.name)
        #expect(names.contains("realAPI"))                  // plain public — kept
        #expect(names.contains("_minimumCapacity") == false) // @_spi — dropped
    }

    @Test("c151: nested local functions are skipped (e.g. binomial inside a computed property)")
    func nestedLocalFunctionsAreSkipped() {
        let source = """
        public struct Seq {
            public var count: Int {
                func binomial(n: Int, k: Int) -> Int { n - k }
                return binomial(n: 4, k: 2)
            }
            public func topLevelMember(_ x: Int) -> Int { x }
        }
        public func freeFunction(_ y: Int) -> Int { y }
        """
        let names = FunctionScanner.scan(source: source, file: "Test.swift").map(\.name)
        #expect(names.contains("topLevelMember"))    // type member — kept
        #expect(names.contains("freeFunction"))      // top-level — kept
        #expect(names.contains("binomial") == false) // nested local — dropped
    }

    @Test("c151: functions in an explicitly non-public enclosing type are skipped (internal enum)")
    func nonPublicEnclosingTypeIsSkipped() {
        let source = """
        internal enum ViolationFormatter {
            static func format(_ x: Int) -> String { "\\(x)" }
        }
        public enum PublicAPI {
            static func format(_ x: Int) -> String { "\\(x)" }
        }
        enum DefaultInternal {
            static func keptByDefault(_ x: Int) -> Int { x }
        }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        let inPublic = summaries.contains { $0.name == "format" && $0.containingTypeName == "PublicAPI" }
        let inInternal = summaries.contains { $0.name == "format" && $0.containingTypeName == "ViolationFormatter" }
        #expect(inPublic)                                          // public type — kept
        #expect(inInternal == false)                              // explicit-internal type — dropped
        #expect(summaries.contains { $0.name == "keptByDefault" }) // default-internal type — kept (fixture shape)
    }
}
