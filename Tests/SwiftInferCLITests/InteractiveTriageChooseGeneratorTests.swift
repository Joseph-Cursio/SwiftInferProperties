import Foundation
@testable import SwiftInferCLI
import Testing

@Suite("InteractiveTriage — chooseGenerator custom-type resolution (#2)")
struct InteractiveTriageChooseGeneratorTests {

    @Test func usesCustomResolverForAProjectType() {
        let suggestion = makeIdempotentSuggestion(funcName: "f", typeName: "Point")
        let resolver: (String) -> String? = { $0 == "Point" ? "DERIVED_POINT_GEN" : nil }
        #expect(
            InteractiveTriage.chooseGenerator(for: suggestion, typeName: "Point", customGenerator: resolver)
                == "DERIVED_POINT_GEN"
        )
    }

    @Test func fallsThroughToStdlibMappingWhenResolverReturnsNil() {
        let suggestion = makeIdempotentSuggestion(funcName: "f", typeName: "Int")
        // A stdlib type has no project shape → resolver returns nil → stdlib generator.
        let resolver: (String) -> String? = { _ in nil }
        #expect(
            InteractiveTriage.chooseGenerator(for: suggestion, typeName: "Int", customGenerator: resolver)
                == "Gen<Int>.int()"
        )
    }

    @Test func fallsBackToGenForCustomTypeWithoutAResolver() {
        let suggestion = makeIdempotentSuggestion(funcName: "f", typeName: "Widget")
        // No resolver supplied → the `Type.gen()` fallback, which now carries the marker saying
        // it is the fallback (#416): four of nineteen emitted stubs were this arm and nothing
        // distinguished them from a resolved generator.
        let generator = InteractiveTriage.chooseGenerator(for: suggestion, typeName: "Widget")
        #expect(generator.hasPrefix("Widget.gen()"))
        #expect(generator.contains("no generator derived"))
    }
}
