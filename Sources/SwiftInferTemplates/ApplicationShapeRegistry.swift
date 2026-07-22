import SwiftInferCore

extension TemplateRegistry {

    /// One **single-function** application-shape template: a `FunctionSummary` in,
    /// at most one `Suggestion` out. This is the single source of truth for that
    /// family — `collectSingleFunctionAppShapes` iterates it to *wire* the
    /// templates, and `ApplicationShapeRegistryTests` iterates the same list to
    /// *prove each one fires through `discover`*. Adding a template here therefore
    /// both wires it and enrolls it in the firing test at once; the coverage gap
    /// that let `filter-subset` ship unit-tested-but-unwired (and left three
    /// siblings the same way — see `docs/roadtest-swiftlintrulestudio.md`) cannot
    /// recur for a template on this list.
    ///
    /// **Pairing-based application shapes (`partition`, `state-machine`) are not
    /// here on purpose** — their input is a *pair* of summaries, not one, so they
    /// do not fit the `(FunctionSummary) -> Suggestion?` shape. They keep their own
    /// collectors and their own firing tests.
    struct SingleFunctionAppShape: Sendable {
        /// The `Suggestion.templateName` this entry emits.
        let name: String
        /// The template's scorer — nil when the summary doesn't match its shape.
        let suggest: @Sendable (FunctionSummary) -> Suggestion?
        /// The `generatorType` passed to `collector.record` (byte-for-byte the
        /// value the hand-written collector used).
        let generatorType: @Sendable (FunctionSummary) -> String?
        /// Mutually-exclusive entries share a group id: within a group, the first
        /// match wins for a given summary and the rest are skipped. The `(T, T) ->
        /// Bool` trio (equivalence ▷ comparator ▷ predicate) is one such group —
        /// the stronger law wins the shared shape. `nil` = fires independently.
        let exclusionGroup: Int?
        /// A summary that MUST make this template fire through `discover`. The
        /// firing test's fixture, and the reason a new entry can't be untested.
        let referenceFixture: FunctionSummary
    }

    /// The registry. Order matters only within an `exclusionGroup` (first wins).
    static let singleFunctionAppShapes: [SingleFunctionAppShape] = [
        SingleFunctionAppShape(
            name: "involution",
            suggest: InvolutionTemplate.suggest(for:),
            generatorType: { $0.returnTypeText },
            exclusionGroup: nil,
            referenceFixture: appShapeFixture(
                "toggled",
                params: [.init(label: nil, internalName: "flag", typeText: "Bool", isInout: false)],
                returns: "Bool"
            )
        ),
        SingleFunctionAppShape(
            name: "reorder-partition",
            suggest: ReorderPartitionTemplate.suggest(for:),
            generatorType: { $0.containingTypeName },
            exclusionGroup: nil,
            referenceFixture: appShapeFixture(
                "partition",
                params: [.init(label: "by", internalName: "belongs", typeText: "(Int) -> Bool", isInout: false)],
                returns: "Int",
                mutating: true,
                on: "Buffer"
            )
        ),
        SingleFunctionAppShape(
            name: "filter-subset",
            suggest: FilterSubsetTemplate.suggest(for:),
            generatorType: { FilterSubsetTemplate.haystackType(of: $0) },
            exclusionGroup: nil,
            referenceFixture: appShapeFixture(
                "filterViolations",
                params: [
                    .init(label: nil, internalName: "violations", typeText: "[Violation]", isInout: false),
                    .init(label: "batch", internalName: "batch", typeText: "[URL]", isInout: false)
                ],
                returns: "[Violation]",
                on: "Analyzer"
            )
        ),
        SingleFunctionAppShape(
            name: "equivalence-relation",
            suggest: EquivalenceRelationTemplate.suggest(for:),
            generatorType: { $0.parameters.first?.typeText },
            exclusionGroup: 0,
            referenceFixture: appShapeFixture(
                "equals",
                params: [
                    .init(label: nil, internalName: "lhs", typeText: "Widget", isInout: false),
                    .init(label: nil, internalName: "rhs", typeText: "Widget", isInout: false)
                ],
                returns: "Bool"
            )
        ),
        SingleFunctionAppShape(
            name: "comparator",
            suggest: ComparatorTemplate.suggest(for:),
            generatorType: { $0.parameters.first?.typeText },
            exclusionGroup: 0,
            referenceFixture: appShapeFixture(
                "precedes",
                params: [
                    .init(label: nil, internalName: "lhs", typeText: "Widget", isInout: false),
                    .init(label: nil, internalName: "rhs", typeText: "Widget", isInout: false)
                ],
                returns: "Bool"
            )
        ),
        SingleFunctionAppShape(
            name: "predicate",
            suggest: PredicateTemplate.suggest(for:),
            generatorType: { $0.parameters.first?.typeText },
            exclusionGroup: 0,
            referenceFixture: appShapeFixture(
                "isValid",
                params: [.init(label: nil, internalName: "value", typeText: "Widget", isInout: false)],
                returns: "Bool"
            )
        )
    ]

    /// Build a reference-fixture `FunctionSummary` with the fields the app-shape
    /// gates read; the rest take their empty defaults.
    private static func appShapeFixture(
        _ name: String,
        params: [Parameter],
        returns: String,
        mutating: Bool = false,
        on containingType: String? = nil
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: params,
            returnTypeText: returns,
            isThrows: false,
            isAsync: false,
            isMutating: mutating,
            isStatic: false,
            location: SourceLocation(file: "AppShapeFixtures.swift", line: 1, column: 1),
            containingTypeName: containingType,
            bodySignals: .empty
        )
    }
}
