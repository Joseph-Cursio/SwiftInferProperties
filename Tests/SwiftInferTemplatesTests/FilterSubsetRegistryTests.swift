import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// Registry-level coverage for `filter-subset` — the template in isolation is
/// pinned by `FilterSubsetTemplateTests`; these pin the parts that live *outside*
/// the template and that a unit test on it cannot see:
///   - the **wiring** (`collectFilterSubsetSuggestions` is actually called by
///     `discover`) — delete the wiring and the isolated test still passes, but
///     these fail;
///   - the **name gate through the whole pipeline** (a `map` shape yields nothing);
///   - the **templateFilter interaction** the road-test reasoned about by hand.
@Suite("Filter-subset — registry wiring & templateFilter")
struct FilterSubsetRegistryTests {

    private static let loc = SourceLocation(file: "Reg.swift", line: 1, column: 1)

    private func param(_ label: String?, _ type: String) -> Parameter {
        Parameter(label: label, internalName: label ?? "value", typeText: type, isInout: false)
    }

    private func fn(_ name: String, params: [Parameter], returns: String) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: params,
            returnTypeText: returns,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: Self.loc,
            containingTypeName: "Analyzer",
            bodySignals: .empty
        )
    }

    /// filterViolations([Violation], [URL], URL) -> [Violation]
    private var filterFn: FunctionSummary {
        fn(
            "filterViolations",
            params: [param(nil, "[Violation]"), param("batch", "[URL]"), param("workspacePath", "URL")],
            returns: "[Violation]"
        )
    }

    /// double([Int]) -> [Int] — a map shape with a non-filter name.
    private var mapFn: FunctionSummary {
        fn("double", params: [param(nil, "[Int]")], returns: "[Int]")
    }

    @Test("discover wires the filter-subset pass — a filter corpus surfaces it")
    func discoverCollectsFilterSubset() {
        let suggestions = TemplateRegistry.discover(in: [filterFn])
        #expect(suggestions.contains { $0.templateName == "filter-subset" })
    }

    @Test("a map-shaped corpus surfaces no filter-subset through the registry")
    func mapShapeYieldsNoFilterSubset() {
        let suggestions = TemplateRegistry.discover(in: [mapFn])
        #expect(!suggestions.contains { $0.templateName == "filter-subset" })
    }

    @Test("templateFilter narrows filter-subset like any other template")
    func templateFilterNarrowsFilterSubset() {
        let corpus = [filterFn]
        let kept = TemplateRegistry.discover(in: corpus, templateFilter: ["filter-subset"])
        #expect(kept.contains { $0.templateName == "filter-subset" })

        let dropped = TemplateRegistry.discover(in: corpus, templateFilter: ["idempotence"])
        #expect(!dropped.contains { $0.templateName == "filter-subset" })
    }
}
