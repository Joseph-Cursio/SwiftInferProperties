import SwiftInferCore
import Testing

/// Recall-widening epic #1 — the scanner surfaces read-only COMPUTED PROPERTIES
/// as nullary `self -> T` summaries (the involution template's instance shape),
/// so `Complex.conjugate` and friends become candidates. Stored properties,
/// read-write pairs, effectful getters, and top-level computed vars are excluded.
@Suite("FunctionScanner — computed-property recognition (recall epic #1)")
struct FunctionScannerComputedPropertyTests {

    private func summaries(_ source: String) -> [FunctionSummary] {
        FunctionScanner.scan(source: source, file: "T.swift")
    }

    @Test("a read-only computed property becomes a nullary self-returning summary")
    func computedPropertyBecomesSummary() throws {
        let source = """
        public struct Complex: Equatable {
            public var re: Int
            public var im: Int
            public var conjugate: Complex { Complex(re: re, im: -im) }
        }
        """
        let conjugate = try #require(summaries(source).first { $0.name == "conjugate" })
        #expect(conjugate.isComputedProperty)
        #expect(conjugate.parameters.isEmpty)
        #expect(conjugate.returnTypeText == "Complex")
        #expect(conjugate.containingTypeName == "Complex")
        #expect(!conjugate.isMutating)
        #expect(!conjugate.isStatic)
    }

    @Test("a STORED property is not a summary")
    func storedPropertyIgnored() {
        let names = summaries("public struct S { public var re: Int = 0 }").map(\.name)
        #expect(!names.contains("re"))
    }

    @Test("a read-WRITE computed property is excluded (getter-only)")
    func getSetPropertyExcluded() {
        let source = """
        public struct S {
            var backing: Int = 0
            public var value: Int { get { backing } set { backing = newValue } }
        }
        """
        #expect(!summaries(source).map(\.name).contains("value"))
    }

    @Test("an effectful (throws/async) getter is excluded")
    func effectfulGetterExcluded() {
        let source = """
        public struct S {
            public var risky: Int { get throws { 0 } }
        }
        """
        #expect(!summaries(source).map(\.name).contains("risky"))
    }

    @Test("a top-level computed var is excluded (no containing type)")
    func topLevelComputedVarExcluded() {
        #expect(!summaries("public var now: Int { 42 }").map(\.name).contains("now"))
    }

    @Test("a private computed property is excluded (not visible to tests)")
    func privateComputedPropertyExcluded() {
        let source = """
        public struct S {
            public var raw: Int = 0
            private var doubled: Int { raw * 2 }
        }
        """
        #expect(!summaries(source).map(\.name).contains("doubled"))
    }
}
