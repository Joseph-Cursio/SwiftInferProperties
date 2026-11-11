import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("IdempotenceTemplate — docstring corroboration (+15, corroborate-only)")
struct IdempotenceDocstringCorroborationTests {

    @Test("Docstring lifts a shape-only candidate Possible 30 -> Likely 45 (surfaces by default)")
    func docstringLiftsShapeOnlyToLikely() throws {
        // `refresh` is not a curated verb, so shape alone = 30 (Possible, hidden).
        let summary = makeIdempotenceSummary(
            name: "refresh",
            returnType: "State",
            paramType: "State",
            docComment: "Recomputes derived state. Calling it on already-current state is idempotent."
        )
        let suggestion = try #require(IdempotenceTemplate.suggest(for: summary))
        #expect(suggestion.score.total == 45)
        #expect(suggestion.score.tier == .likely)
        #expect(suggestion.score.tier.isVisibleByDefault)
    }

    @Test("Docstring lifts a curated-verb candidate Likely 70 -> Strong 85")
    func docstringLiftsCuratedToStrong() throws {
        let summary = makeIdempotenceSummary(
            name: "normalize",
            returnType: "String",
            paramType: "String",
            docComment: "Returns the canonical form of the input."
        )
        let suggestion = try #require(IdempotenceTemplate.suggest(for: summary))
        #expect(suggestion.score.total == 85)
        #expect(suggestion.score.tier == .strong)
    }

    @Test("A negated docstring does not corroborate — score stays 30")
    func negatedDocstringDoesNotBoost() throws {
        let summary = makeIdempotenceSummary(
            name: "advance",
            returnType: "State",
            paramType: "State",
            docComment: "Advances the cursor by one. This is not idempotent."
        )
        let suggestion = try #require(IdempotenceTemplate.suggest(for: summary))
        #expect(suggestion.score.total == 30)
        #expect(suggestion.score.tier == .possible)
    }

    @Test("A non-matching shape earns no candidate even with idempotence prose (corroborate-only)")
    func docstringAloneNeverSurfaces() {
        // `(A) -> B` is not the idempotence shape; the docstring must not conjure a law.
        let summary = makeIdempotenceSummary(
            name: "encode",
            returnType: "Data",
            paramType: "Model",
            docComment: "Encodes the model. The operation is idempotent."
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }

    @Test("The corroboration signal is rendered in the explainability block")
    func corroborationSignalRendered() throws {
        let summary = makeIdempotenceSummary(
            name: "process",
            returnType: "String",
            paramType: "String",
            docComment: "Idempotent cleanup pass."
        )
        let suggestion = try #require(IdempotenceTemplate.suggest(for: summary))
        let why = suggestion.explainability.whySuggested.joined(separator: "\n")
        #expect(why.contains("Docstring corroborates idempotence"))
        #expect(why.contains("idempotent"))
    }
}
