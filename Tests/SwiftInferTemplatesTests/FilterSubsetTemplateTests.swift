import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The filter role and its one refutable free law — **subset**,
/// `Set(result) ⊆ Set(haystack)`. Fires on a curated filter/selection name
/// returning `[T]` where some parameter is `[T]` (the collection being filtered).
/// A `map`-shaped `[T] -> [T]` (a non-filter name) does NOT fire — subset is a
/// false law for it (`[1,2] -> [2,4]`), which is why the name gates the shape.
@Suite("Filter — subset of the collection it selects from")
struct FilterSubsetTemplateTests {

    private static let loc = SourceLocation(file: "Filters.swift", line: 1, column: 1)

    private func filterFn(
        _ name: String,
        params: [Parameter],
        returns: String?,
        on type: String? = "Analyzer",
        mutating: Bool = false,
        async: Bool = false,
        throws throwing: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: params,
            returnTypeText: returns,
            isThrows: throwing,
            isAsync: async,
            isMutating: mutating,
            isStatic: false,
            location: Self.loc,
            containingTypeName: type,
            bodySignals: .empty
        )
    }

    private func param(_ label: String?, _ type: String) -> Parameter {
        Parameter(label: label, internalName: label ?? "value", typeText: type, isInout: false)
    }

    // MARK: - Fires

    @Test("a multi-arg filter (filterViolations) owes subset, at Possible")
    func multiArgFilterFires() throws {
        // filterViolations([Violation], [URL], URL) -> [Violation]
        let fn = filterFn(
            "filterViolations",
            params: [param(nil, "[Violation]"), param("batch", "[URL]"), param("workspacePath", "URL")],
            returns: "[Violation]"
        )
        #expect(FilterSubsetTemplate.isFilter(fn))

        let suggestion = try #require(FilterSubsetTemplate.suggest(for: fn))
        #expect(suggestion.templateName == "filter-subset")
        #expect(suggestion.score.tier == .possible)
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(caveats.contains("⊆"))  // the subset law `Set(result) ⊆ Set(haystack)`
    }

    @Test("a single-arg selector (select) fires")
    func singleArgSelectFires() {
        let fn = filterFn("selectRules", params: [param(nil, "[Rule]")], returns: "[Rule]")
        #expect(FilterSubsetTemplate.isFilter(fn))
    }

    // MARK: - Does not fire

    @Test("a map-shaped [Int] -> [Int] with a non-filter name does NOT fire")
    func mapShapeRejected() {
        // `double` returns [Int] and takes [Int], but is not a filter — subset is false for it.
        let fn = filterFn("double", params: [param(nil, "[Int]")], returns: "[Int]")
        #expect(FilterSubsetTemplate.isFilter(fn) == false)
        #expect(FilterSubsetTemplate.suggest(for: fn) == nil)
    }

    @Test("a filter name whose return element matches no parameter does NOT fire")
    func returnElementMismatchRejected() {
        // filterNames([Rule]) -> [String]: no [String] parameter to be a subset of.
        let fn = filterFn("filterNames", params: [param(nil, "[Rule]")], returns: "[String]")
        #expect(FilterSubsetTemplate.isFilter(fn) == false)
    }

    @Test("a non-collection return does NOT fire")
    func scalarReturnRejected() {
        let fn = filterFn("filterCount", params: [param(nil, "[Rule]")], returns: "Int")
        #expect(FilterSubsetTemplate.isFilter(fn) == false)
    }

    @Test("a mutating filter does NOT fire")
    func mutatingRejected() {
        let fn = filterFn("filterInPlace", params: [param(nil, "[Rule]")], returns: "[Rule]", mutating: true)
        #expect(FilterSubsetTemplate.isFilter(fn) == false)
    }

    @Test("an async filter does NOT fire")
    func asyncRejected() {
        let fn = filterFn("filterRemotely", params: [param(nil, "[Rule]")], returns: "[Rule]", async: true)
        #expect(FilterSubsetTemplate.isFilter(fn) == false)
    }
}
