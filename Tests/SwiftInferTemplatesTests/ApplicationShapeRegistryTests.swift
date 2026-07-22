import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The parameterized coverage the road-test asked for: instead of one hand-written
/// registry test per template (the pattern that let `filter-subset` and three
/// siblings ship unit-tested-but-unwired), these iterate
/// `TemplateRegistry.singleFunctionAppShapes` — so a new entry is proven to fire
/// through `discover` automatically, and a wiring omission is a red test, not a
/// coverage-report archaeology dig.
@Suite("Application-shape registry — firing coverage")
struct ApplicationShapeRegistryTests {

    @Test("every registered single-function app-shape fires through discover on its fixture")
    func everyEntryFiresThroughDiscover() {
        for entry in TemplateRegistry.singleFunctionAppShapes {
            let suggestions = TemplateRegistry.discover(in: [entry.referenceFixture])
            #expect(
                suggestions.contains { $0.templateName == entry.name },
                "template '\(entry.name)' did not fire through discover on its reference fixture"
            )
        }
    }

    @Test("each reference fixture still triggers its own template directly")
    func eachFixtureTriggersItsTemplate() {
        for entry in TemplateRegistry.singleFunctionAppShapes {
            #expect(
                entry.suggest(entry.referenceFixture) != nil,
                "reference fixture for '\(entry.name)' no longer triggers its template"
            )
        }
    }

    @Test("the (T,T)->Bool trio is mutually exclusive — a comparator is not also a predicate")
    func trioMutualExclusion() throws {
        let comparator = try #require(
            TemplateRegistry.singleFunctionAppShapes.first { $0.name == "comparator" }
        )
        let suggestions = TemplateRegistry.discover(in: [comparator.referenceFixture])
        #expect(suggestions.contains { $0.templateName == "comparator" })
        #expect(!suggestions.contains { $0.templateName == "predicate" })
    }
}
