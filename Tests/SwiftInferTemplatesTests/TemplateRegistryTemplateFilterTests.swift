import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

/// V1.32.B — `templateFilter: Set<String>?` parameter on
/// `TemplateRegistry.discover`. Verifies the filter drops suggestions
/// whose `templateName` is outside the allowed set while leaving
/// suggestions inside the set untouched. Nil filter preserves the
/// monolithic-registry behavior bit-for-bit.
@Suite("TemplateRegistry — V1.32.B templateFilter parameter")
struct TemplateRegistryTemplateFilterTests {

    // MARK: - Fixtures

    /// A binary commutative-shaped function `(T, T) -> T` over a curated
    /// type — surfaces commutativity + associativity (numeric / algebraic
    /// packs).
    private static let binaryOp = FunctionSummary(
        name: "add",
        parameters: [
            Parameter(label: nil, internalName: "lhs", typeText: "Int", isInout: false),
            Parameter(label: nil, internalName: "rhs", typeText: "Int", isInout: false)
        ],
        returnTypeText: "Int",
        isThrows: false,
        isAsync: false,
        isMutating: false,
        isStatic: false,
        location: SourceLocation(file: "Test.swift", line: 1, column: 1),
        containingTypeName: "Int",
        bodySignals: .empty
    )

    /// A `T -> T` unary function with a curated idempotence verb —
    /// surfaces idempotence (collections / algebraic packs).
    private static let unaryIdem = FunctionSummary(
        name: "normalize",
        parameters: [
            Parameter(label: nil, internalName: "input", typeText: "String", isInout: false)
        ],
        returnTypeText: "String",
        isThrows: false,
        isAsync: false,
        isMutating: false,
        isStatic: false,
        location: SourceLocation(file: "Test.swift", line: 10, column: 1),
        containingTypeName: nil,
        bodySignals: .empty
    )

    // MARK: - Nil filter preserves all-templates behavior

    @Test("V1.32.B — nil templateFilter is the monolithic-registry default")
    func nilFilterPreservesMonolithic() {
        let withoutFilter = TemplateRegistry.discover(
            in: [Self.binaryOp, Self.unaryIdem]
        )
        let withNilFilter = TemplateRegistry.discover(
            in: [Self.binaryOp, Self.unaryIdem],
            templateFilter: nil
        )
        #expect(withoutFilter.count == withNilFilter.count)
        #expect(Set(withoutFilter.map(\.identity)) == Set(withNilFilter.map(\.identity)))
    }

    // MARK: - Empty filter suppresses everything

    @Test("V1.32.B — empty templateFilter returns zero suggestions")
    func emptyFilterReturnsZero() {
        let filtered = TemplateRegistry.discover(
            in: [Self.binaryOp, Self.unaryIdem],
            templateFilter: []
        )
        #expect(filtered.isEmpty)
    }

    // MARK: - Single-pack filter

    @Test("V1.32.B — algebraic pack keeps commutativity/associativity/idempotence")
    func algebraicPackFilters() {
        let algebraic = TemplatePack.algebraic.templateNames
        let filtered = TemplateRegistry.discover(
            in: [Self.binaryOp, Self.unaryIdem],
            templateFilter: algebraic
        )
        // All survivors must be in the algebraic pack
        for suggestion in filtered {
            #expect(
                algebraic.contains(suggestion.templateName),
                "Survivor template '\(suggestion.templateName)' is outside the algebraic pack"
            )
        }
    }

    @Test("V1.32.B — serialization pack filters out commutativity / idempotence")
    func serializationPackExcludesAlgebraic() {
        // The binaryOp + unaryIdem fixtures don't surface round-trip /
        // inverse-pair, so the serialization pack should produce an
        // empty filtered result.
        let filtered = TemplateRegistry.discover(
            in: [Self.binaryOp, Self.unaryIdem],
            templateFilter: TemplatePack.serialization.templateNames
        )
        for suggestion in filtered {
            #expect(["round-trip", "inverse-pair"].contains(suggestion.templateName))
        }
    }

    // MARK: - resolve(_ packs:) integration

    @Test("V1.32.B — TemplatePack.resolve(_:) feeds templateFilter correctly")
    func resolveIntegratesWithDiscover() {
        let union = TemplatePack.resolve([.numeric, .algebraic])
        let filtered = TemplateRegistry.discover(
            in: [Self.binaryOp, Self.unaryIdem],
            templateFilter: union
        )
        // All survivors must be in the union of numeric ∪ algebraic packs
        for suggestion in filtered {
            #expect(
                union.contains(suggestion.templateName),
                "Survivor template '\(suggestion.templateName)' is outside numeric ∪ algebraic"
            )
        }
    }

    @Test("V1.32.B — allTemplateNames filter is equivalent to nil filter")
    func allTemplateNamesEquivalentToNil() {
        let withNilFilter = TemplateRegistry.discover(
            in: [Self.binaryOp, Self.unaryIdem],
            templateFilter: nil
        )
        let withAllFilter = TemplateRegistry.discover(
            in: [Self.binaryOp, Self.unaryIdem],
            templateFilter: TemplatePack.allTemplateNames
        )
        #expect(Set(withNilFilter.map(\.identity)) == Set(withAllFilter.map(\.identity)))
    }

    // MARK: - Suggestions remain sorted after filtering

    @Test("V1.32.B — filtered output preserves the sortSuggestions ordering")
    func filteredOutputIsSorted() {
        let filtered = TemplateRegistry.discover(
            in: [Self.binaryOp, Self.unaryIdem],
            templateFilter: TemplatePack.algebraic.templateNames
        )
        // Scores should be in descending order (the sortSuggestions
        // contract for the monolithic path applies identically to
        // the filtered path).
        let scores = filtered.map(\.score.total)
        #expect(scores == scores.sorted(by: >))
    }
}
