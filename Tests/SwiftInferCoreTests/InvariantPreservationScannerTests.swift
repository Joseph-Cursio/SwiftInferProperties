import Testing
@testable import SwiftInferCore

@Suite("FunctionScanner — @CheckProperty(.preservesInvariant(_:)) detection (M7.2)")
struct InvariantPreservationScannerTests {

    @Test
    func unannotatedFunctionLeavesInvariantKeypathNil() throws {
        let source = """
        func mutate(_ value: Widget) -> Widget { value }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        let summary = try #require(summaries.first)
        #expect(summary.invariantKeypath == nil)
    }

    @Test
    func preservesInvariantAttributeWithKeypathArgumentIsExtracted() throws {
        let source = """
        @CheckProperty(.preservesInvariant(\\.isValid))
        func adjust(_ value: Widget) -> Widget { value }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        let summary = try #require(summaries.first)
        #expect(summary.invariantKeypath == "\\.isValid")
    }

    @Test
    func preservesInvariantOnFunctionInsideTypeContextIsDetected() throws {
        let source = """
        struct Widget {
            @CheckProperty(.preservesInvariant(\\.isValid))
            func adjusted() -> Widget { self }
        }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        let summary = try #require(summaries.first)
        #expect(summary.invariantKeypath == "\\.isValid")
        #expect(summary.containingTypeName == "Widget")
    }

    @Test
    func checkPropertyIdempotentArmDoesNotMatch() throws {
        let source = """
        @CheckProperty(.idempotent)
        func normalize(_ value: String) -> String { value }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        let summary = try #require(summaries.first)
        #expect(summary.invariantKeypath == nil)
    }

    @Test
    func checkPropertyRoundTripArmDoesNotMatch() throws {
        let source = """
        @CheckProperty(.roundTrip(pairedWith: "decode"))
        func encode(_ value: MyType) -> Data { Data() }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        let summary = try #require(summaries.first)
        #expect(summary.invariantKeypath == nil)
    }

    @Test
    func nonKeypathArgumentFallsThroughToNil() throws {
        // Defensive — `.preservesInvariant("isValid")` (string instead of
        // keypath) and `.preservesInvariant(42)` (integer) aren't
        // representable as a stable keypath at scan time. Treat as
        // malformed → no signal, no suggestion. M7 plan calls for a
        // diagnostic on this path; M7.2 ships the suppression silently
        // (diagnostic wiring lands when a scanner-side stderr sink is
        // added in a later sub-milestone).
        let source = """
        @CheckProperty(.preservesInvariant("isValid"))
        func adjust(_ value: Widget) -> Widget { value }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        let summary = try #require(summaries.first)
        #expect(summary.invariantKeypath == nil)
    }

    @Test
    func qualifiedCheckPropertyAttributeIsRecognized() throws {
        // Users who want explicit qualification can write
        // `@SwiftInferMacro.CheckProperty(...)`. Recognize-only matches
        // the trailing identifier component, not the full dotted path.
        let source = """
        @SwiftInferMacro.CheckProperty(.preservesInvariant(\\.isValid))
        func adjust(_ value: Widget) -> Widget { value }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        let summary = try #require(summaries.first)
        #expect(summary.invariantKeypath == "\\.isValid")
    }

    @Test
    func multipleAttributesRecognisePreservesInvariantAlongsideOthers() throws {
        let source = """
        @available(macOS 14, *)
        @CheckProperty(.preservesInvariant(\\.isValid))
        @inlinable
        public func adjust(_ value: Widget) -> Widget { value }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        let summary = try #require(summaries.first)
        #expect(summary.invariantKeypath == "\\.isValid")
    }

    @Test
    func nestedKeypathIsCapturedAsWritten() throws {
        let source = """
        @CheckProperty(.preservesInvariant(\\.account.balance))
        func transfer(_ user: User) -> User { user }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        let summary = try #require(summaries.first)
        #expect(summary.invariantKeypath == "\\.account.balance")
    }

    @Test
    func preservesInvariantOnNestedFunctionDoesNotPropagateToOuter() throws {
        // Mirrors the `@Discoverable` posture — the scanner skips nested
        // function bodies, so an annotation on an inner function doesn't
        // leak to the outer summary.
        let source = """
        func outer(_ value: Widget) -> Widget {
            @CheckProperty(.preservesInvariant(\\.isValid))
            func inner() -> Widget { value }
            return inner()
        }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        let summary = try #require(summaries.first)
        #expect(summary.name == "outer")
        #expect(summary.invariantKeypath == nil)
    }
}
