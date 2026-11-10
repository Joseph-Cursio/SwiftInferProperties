import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("ContradictionDetector — empty + passthrough cases")
struct ContradictionDetectorEmptyTests {

    @Test
    func emptySuggestionsYieldEmptyOutcome() {
        let outcome = ContradictionDetector.filter(
            [],
            typesToCheck: [:],
            resolver: EquatableResolver(typeDecls: [])
        )
        #expect(outcome.kept.isEmpty)
        #expect(outcome.dropped.isEmpty)
    }

    @Test
    func suggestionAbsentFromTypesToCheckPassesThrough() throws {
        let (suggestion, _) = try makeCommutativitySuggestion(type: "Int")
        // Empty typesToCheck — detector treats this as keep (M3.4
        // restricts the contradiction layer to suggestions whose types
        // were registered by the producer).
        let outcome = ContradictionDetector.filter(
            [suggestion],
            typesToCheck: [:],
            resolver: EquatableResolver(typeDecls: [])
        )
        #expect(outcome.kept == [suggestion])
        #expect(outcome.dropped.isEmpty)
    }
}
