import Testing
@testable import SwiftInferCore

@Suite("FunctionScanner — @Discoverable(group:) detection (M5.1)")
struct DiscoverableAnnotationScannerTests {

    @Test
    func unannotatedFunctionLeavesDiscoverableGroupNil() throws {
        let source = """
        func normalize(_ value: String) -> String { value }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        let summary = try #require(summaries.first)
        #expect(summary.discoverableGroup == nil)
    }

    @Test
    func discoverableAttributeWithGroupArgumentIsExtracted() throws {
        let source = """
        @Discoverable(group: "codec")
        func encode(_ value: MyType) -> Data { Data() }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        let summary = try #require(summaries.first)
        #expect(summary.discoverableGroup == "codec")
    }

    @Test
    func discoverableAttributeWithoutGroupArgumentLeavesGroupNil() throws {
        // The kit's `@Discoverable` macro lets users omit the `group:`
        // argument entirely (per ProtoLawMacro's M5 advisory). When
        // that happens there's no group to scope on — recognize-only
        // mode treats the attribute as absent for SwiftInfer's purposes.
        let source = """
        @Discoverable
        func encode(_ value: MyType) -> Data { Data() }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        let summary = try #require(summaries.first)
        #expect(summary.discoverableGroup == nil)
    }

    @Test
    func discoverableAttributeWithEmptyParensLeavesGroupNil() throws {
        let source = """
        @Discoverable()
        func encode(_ value: MyType) -> Data { Data() }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        let summary = try #require(summaries.first)
        #expect(summary.discoverableGroup == nil)
    }

    @Test
    func multipleAttributesRecogniseDiscoverableAlongsideOthers() throws {
        // Function carries both an unrelated attribute and a
        // `@Discoverable(group:)` — the scanner must not be thrown off
        // by the attribute-list ordering.
        let source = """
        @available(macOS 14, *)
        @Discoverable(group: "queue")
        @inlinable
        public func enqueue(_ job: Job) -> Job? { job }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        let summary = try #require(summaries.first)
        #expect(summary.discoverableGroup == "queue")
    }

    @Test
    func qualifiedDiscoverableAttributeIsRecognized() throws {
        // Users who want explicit qualification can write
        // `@ProtoLawMacro.Discoverable(...)`. Recognize-only matches
        // the trailing identifier component, not the full dotted path.
        let source = """
        @ProtoLawMacro.Discoverable(group: "graph")
        func unionGraphs(_ a: Graph, _ b: Graph) -> Graph { a }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        let summary = try #require(summaries.first)
        #expect(summary.discoverableGroup == "graph")
    }

    @Test
    func interpolatedStringLiteralFallsThroughToNil() throws {
        // String interpolation in attribute arguments resolves at
        // expansion time — not representable as a stable group at
        // scan time. Conservative: treat as no group.
        let source = """
        @Discoverable(group: "codec\\(0)")
        func encode(_ value: MyType) -> Data { Data() }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        let summary = try #require(summaries.first)
        #expect(summary.discoverableGroup == nil)
    }

    @Test
    func nonStringLiteralGroupArgumentFallsThroughToNil() throws {
        // Defensive — non-string-literal `group:` values (e.g. a
        // member-access reference like `Group.codec`) aren't
        // representable as a flat string at scan time. Treat as no
        // group rather than guess at the type's runtime value.
        let source = """
        @Discoverable(group: Group.codec)
        func encode(_ value: MyType) -> Data { Data() }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        let summary = try #require(summaries.first)
        #expect(summary.discoverableGroup == nil)
    }

    @Test
    func discoverableOnNestedFunctionDoesNotPropagateToOuter() throws {
        // The scanner intentionally skips nested-function bodies (per
        // the FunctionScanner doc), so a `@Discoverable` on a nested
        // function never surfaces. The outer function's group field
        // stays nil.
        let source = """
        func outer(_ value: String) -> String {
            @Discoverable(group: "nested")
            func inner() -> String { "x" }
            return inner()
        }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        let summary = try #require(summaries.first)
        #expect(summary.name == "outer")
        #expect(summary.discoverableGroup == nil)
    }

    @Test
    func attributeOnFunctionInsideTypeContextIsDetected() throws {
        // Typical placement is inside a type body. The visitor walks
        // members and the attribute lives on the inner func decl.
        let source = """
        struct Codec {
            @Discoverable(group: "codec")
            func encode(_ value: MyType) -> Data { Data() }
        }
        """
        let summaries = FunctionScanner.scan(source: source, file: "Test.swift")
        let summary = try #require(summaries.first)
        #expect(summary.discoverableGroup == "codec")
        #expect(summary.containingTypeName == "Codec")
    }
}
