import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("IdempotenceTemplate (non-lifted) — V1.39.D Constraint equivalence")
struct IdempotenceConstraintEquivalenceTests {

    private static let loc = SourceLocation(file: "T.swift", line: 1, column: 1)

    private static func summary(
        name: String,
        type: String = "Foo"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: nil, internalName: "x", typeText: type, isInout: false)],
            returnTypeText: type,
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: loc,
            containingTypeName: type,
            bodySignals: .empty
        )
    }

    @Test("V1.39.D — Idempotence non-lifted: wrapper matches Constraint output across corpus")
    func equivalence() {
        let corpus: [(label: String, summary: FunctionSummary)] = [
            ("curated_normalize", Self.summary(name: "normalize")),
            ("bare_someOp", Self.summary(name: "someOp")),
            ("math_log", Self.summary(name: "log", type: "Double")),
        ]
        for (label, summary) in corpus {
            let wrapper = IdempotenceTemplate.suggest(for: summary)
            let runner = ConstraintRunner.suggest(
                constraint: IdempotenceTemplate.makeConstraint(
                    vocabulary: .empty,
                    inheritedTypesByName: [:],
                    carrierKindResolver: nil
                ),
                subject: summary
            )
            #expect(wrapper == runner, "[\(label)] disagree")
        }
    }
}
