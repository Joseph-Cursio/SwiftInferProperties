import Foundation
import SwiftInferCore
import Testing

// Non-public / SPI scan-time CLASSIFICATION (cycles 54 / 148 / 151; inverted 2026-08-07).
// Split out of FunctionScannerTests.swift (cycle 151) to keep that struct under SwiftLint's
// type_body_length cap.
//
// These cycles once *removed* each non-public shape from `summaries` — an external verifier
// can never call it, so it looked like noise. That reasoning does not survive refactoring-safe
// property discovery: a `private` helper has a real law, and an app's pure logic lives almost
// entirely in `private` helpers. So the shapes are no longer withheld; they are SURFACED into
// `summaries` (discoverable like any function) and simultaneously recorded in `restricted` with
// the reason that becomes the access caveat ("widen to `internal`", "lift the local out", …).
// The taxonomy the cycles built is intact — it now classifies rather than excludes.
@Suite("FunctionScanner — non-public / SPI classification")
struct FunctionScannerAccessFilterTests {

    // MARK: V1.57.A (cycle 54) + cycle-148 (Lever A)

    @Test("access filter: every access level surfaces; non-public ones carry a restriction (c148)")
    func nonPublicAccessLevelsAreClassified() {
        let source = """
        public func publicFn() {}
        private func privateFn() {}
        fileprivate func fileprivateFn() {}
        internal func internalFn() {}
        func defaultFn() {}
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let names = corpus.summaries.map(\.name)
        // Every declaration now reaches discovery — nothing is dropped.
        #expect(names.contains("publicFn"))
        #expect(names.contains("defaultFn"))
        #expect(names.contains("internalFn"))
        #expect(names.contains("privateFn"))
        #expect(names.contains("fileprivateFn"))
        #expect(corpus.summaries.count == 5)
        // The non-public ones are also classified, so a caveat attaches.
        #expect(restriction(of: "privateFn", in: corpus) == .notVisibleToTests)
        #expect(restriction(of: "fileprivateFn", in: corpus) == .notVisibleToTests)
        #expect(restriction(of: "internalFn", in: corpus) == .internalOrSPI)
        // public + default-internal carry no restriction (no caveat needed).
        #expect(restriction(of: "publicFn", in: corpus) == nil)
        #expect(restriction(of: "defaultFn", in: corpus) == nil)
    }

    @Test("c148: access modifier (not `_` prefix) decides the restriction — public `_relaxedAdd` unrestricted")
    func underscoreNamedPublicSPIIsClassifiedByAccess() {
        // The reliable signal is access level, not the `_` name: swift-numerics ships
        // `public static func _relaxedAdd` (underscore-named but PUBLIC), while
        // swift-collections' `internal mutating func _ensureUnique` is real internal SPI.
        let source = """
        public func _relaxedAdd() {}
        internal func _ensureUnique() {}
        func _defaultInternalHelper() {}
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let names = corpus.summaries.map(\.name)
        #expect(names.contains("_relaxedAdd"))
        #expect(names.contains("_defaultInternalHelper"))
        #expect(names.contains("_ensureUnique"))
        #expect(restriction(of: "_relaxedAdd", in: corpus) == nil)            // public — no caveat
        #expect(restriction(of: "_defaultInternalHelper", in: corpus) == nil) // default-internal — no caveat
        #expect(restriction(of: "_ensureUnique", in: corpus) == .internalOrSPI)
    }

    @Test("cycle 148: functions in a `_`-prefixed enclosing type / extension surface with a restriction")
    func underscoreEnclosingTypesAreClassified() {
        let source = """
        public struct Keep { public func ok() {} }
        public struct _HashTable { public func wordCount() {} }
        extension _UnsafeHashTable { public func word() {} }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let names = corpus.summaries.map(\.name)
        #expect(names.contains("ok"))
        #expect(names.contains("wordCount"))
        #expect(names.contains("word"))
        #expect(restriction(of: "ok", in: corpus) == nil)
        #expect(restriction(of: "wordCount", in: corpus) == .internalOrSPI)
        #expect(restriction(of: "word", in: corpus) == .internalOrSPI)
    }

    // MARK: cycle 151 (Lever D) — @_spi / nested-local / non-public-type

    @Test("c151: @_spi(...) declarations surface, classified internal/SPI")
    func spiDeclarationsAreClassified() {
        let source = """
        public struct Box {
            @_spi(Testing) public static func _minimumCapacity(forScale s: Int) -> Int { s }
            public static func realAPI(_ x: Int) -> Int { x }
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let names = corpus.summaries.map(\.name)
        #expect(names.contains("realAPI"))
        #expect(names.contains("_minimumCapacity"))
        #expect(restriction(of: "realAPI", in: corpus) == nil)
        #expect(restriction(of: "_minimumCapacity", in: corpus) == .internalOrSPI)
    }

    @Test("c151: nested local functions surface, classified as nested-local (remedy: lift it out)")
    func nestedLocalFunctionsAreClassified() {
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
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let names = corpus.summaries.map(\.name)
        #expect(names.contains("topLevelMember"))
        #expect(names.contains("freeFunction"))
        #expect(names.contains("binomial"))
        #expect(restriction(of: "binomial", in: corpus) == .nestedLocal)
    }

    @Test("c151: functions in an explicitly non-public enclosing type surface, classified")
    func nonPublicEnclosingTypeIsClassified() {
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
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let inPublic = corpus.summaries.contains {
            $0.name == "format" && $0.containingTypeName == "PublicAPI"
        }
        let inInternal = corpus.summaries.contains {
            $0.name == "format" && $0.containingTypeName == "ViolationFormatter"
        }
        #expect(inPublic)     // public type — surfaced, no caveat
        #expect(inInternal)   // explicit-internal type — surfaced, classified
        #expect(corpus.summaries.contains { $0.name == "keptByDefault" })
        // The internal-enum member carries a restriction; the default-internal one does not.
        let internalMember = corpus.restricted.first {
            $0.summary.name == "format" && $0.summary.containingTypeName == "ViolationFormatter"
        }
        #expect(internalMember?.restriction == .internalOrSPI)
        #expect(corpus.restricted.contains { $0.summary.name == "keptByDefault" } == false)
    }

    /// The restriction the scan recorded for `name`, or `nil` if it surfaced unrestricted.
    private func restriction(
        of name: String,
        in corpus: ScannedCorpus
    ) -> AccessRestriction? {
        corpus.restricted.first { $0.summary.name == name }?.restriction
    }
}
