import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("IdempotenceTemplate — optional-narrowing shape")
struct IdempotenceOptionalNarrowingTests {

    // An optional-narrowing shape `(T?) -> T` is still idempotence-well-formed:
    // `f(f(x))` typechecks because the non-optional result promotes back to `T?`.
    // (E.g. `mergedWith(existing: [String]?) -> [String]`.)
    @Test("Optional-narrowing T? -> T matches the type-symmetry signal")
    func optionalNarrowingMatches() {
        let summary = makeIdempotenceSummary(
            name: "process",
            paramType: "[String]?",
            returnType: "[String]"
        )
        let suggestion = IdempotenceTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 30)
        #expect(suggestion?.score.tier == .possible)
    }

    @Test("Optional param whose base differs from the return type does not match")
    func optionalDifferentBaseDoesNotMatch() {
        let summary = makeIdempotenceSummary(
            name: "process",
            paramType: "Int?",
            returnType: "String"
        )
        #expect(IdempotenceTemplate.suggest(for: summary) == nil)
    }
}
