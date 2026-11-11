import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("InvariantPreservationTemplate — V1.38.D Constraint equivalence")
struct InvariantPreservationEquivTests {

    private static let location = SourceLocation(file: "T.swift", line: 1, column: 1)

    private static func summary(
        name: String = "apply",
        invariantKeypath: String? = nil,
        bodySignals: BodySignals = .empty
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(label: nil, internalName: "x", typeText: "Foo", isInout: false)
            ],
            returnTypeText: "Foo",
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: location,
            containingTypeName: "Foo",
            bodySignals: bodySignals,
            invariantKeypath: invariantKeypath
        )
    }

    @Test("V1.38.D — InvariantPreservation: wrapper matches Constraint output across corpus")
    func equivalence() {
        let corpus: [(label: String, summary: FunctionSummary)] = [
            ("missingKeypath_noFire", Self.summary()),
            ("withKeypath_isValid", Self.summary(invariantKeypath: "\\.isValid")),
            ("nonDeterministic_veto", Self.summary(
                invariantKeypath: "\\.isValid",
                bodySignals: BodySignals(
                    hasNonDeterministicCall: true,
                    hasSelfComposition: false,
                    nonDeterministicAPIsDetected: ["Date()"]
                )
            )),
        ]
        for (label, summary) in corpus {
            let wrapper = InvariantPreservationTemplate.suggest(for: summary)
            let runner = ConstraintRunner.suggest(
                constraint: InvariantPreservationTemplate.makeConstraint(),
                subject: summary
            )
            #expect(wrapper == runner, "[\(label)] disagree")
        }
    }

    @Test("V1.38.D — InvariantPreservation: missing keypath gate returns nil")
    func missingKeypathReturnsNil() {
        #expect(InvariantPreservationTemplate.suggest(for: Self.summary()) == nil)
    }

    @Test("V1.38.D — InvariantPreservation: keypath flows into caveat text")
    func caveatMentionsKeypath() throws {
        let suggestion = try #require(
            InvariantPreservationTemplate.suggest(for: Self.summary(invariantKeypath: "\\.isHealthy"))
        )
        let keypathCaveat = suggestion.explainability.whyMightBeWrong[0]
        #expect(keypathCaveat.contains("\\.isHealthy"))
    }
}
