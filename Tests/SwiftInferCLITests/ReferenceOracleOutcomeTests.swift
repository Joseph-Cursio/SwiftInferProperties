import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// `referenceOracleOutcome` and its draws, on hand-built rows: the cases no fixture reaches
/// through `discover`.
@Suite("Reference oracle — the outcome, decided row by row")
struct ReferenceOracleOutcomeTests {

    private static let file = "/fixture/Source.swift"

    private static func summary(
        name: String,
        owner: String?,
        parameters: [Parameter],
        isStatic: Bool = true,
        isInitializer: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: "Int",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: isStatic,
            location: SourceLocation(file: file, line: 3, column: 5),
            containingTypeName: owner,
            bodySignals: .empty,
            isInitializer: isInitializer,
            docComment: "Returns the count, never negative."
        )
    }

    private static func law(for summary: FunctionSummary, mock: MockGenerator? = nil) -> Suggestion {
        var law = Suggestion(
            templateName: "determinism",
            evidence: [summary.inferenceEvidence],
            score: Score(signals: [Signal(kind: .deterministicPurity, weight: 30, detail: "")]),
            generator: GeneratorMetadata(
                source: mock == nil ? .notYetComputed : .inferredFromTests, confidence: nil, sampling: .notRun
            ),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "determinism|\(summary.name)")
        )
        law.mockGenerator = mock
        return law
    }

    private static let fallback = DocstringAdvisory.fallbackContract(
        .init(docComment: "Returns the count, never negative.", redHerrings: [])
    )

    private static func parameter(_ label: String?, _ name: String, _ type: String) -> Parameter {
        Parameter(label: label, internalName: name, typeText: type, isInout: false)
    }

    /// The scan makes initializer rows only synthetically, so discover never reaches one today; if
    /// one does, its call has no `CalleeReference` form and it is declined by name.
    @Test func anInitializerIsDeclined() {
        let initializer = Self.summary(
            name: "init", owner: "Budget", parameters: [Self.parameter("limit", "limit", "Int")], isInitializer: true
        )
        let outcome = SwiftInferCommand.Discover.referenceOracleOutcome(
            for: initializer,
            advisory: Self.fallback,
            suggestions: [Self.law(for: initializer)],
            context: .unscanned
        )
        #expect(outcome == .declined(
            "`Budget.init(limit:)` is an initializer; the reference oracle calls functions and methods only"
        ))
    }

    /// `chooseGenerator` hands back a suggestion's mock for EVERY type it is asked for. The oracle
    /// draws a receiver and arguments of different types, so the mock answers for its own type only.
    @Test func aMockAnswersForItsOwnTypeOnly() {
        let method = Self.summary(
            name: "scaled", owner: "Ruler", parameters: [Self.parameter(nil, "length", "Int")], isStatic: false
        )
        let mock = MockGenerator(
            typeName: "Ruler",
            argumentSpec: [.init(label: "unit", swiftTypeName: "Int", observedLiterals: ["3"])],
            siteCount: 2
        )
        let law = Self.law(for: method, mock: mock)
        let receiver = SwiftInferCommand.Discover.oracleGenerator(for: law, typeName: "Ruler", context: .unscanned)
        let argument = SwiftInferCommand.Discover.oracleGenerator(for: law, typeName: "Int", context: .unscanned)
        #expect(receiver == LiftedTestEmitter.mockInferredGenerator(mock))
        #expect(argument == InteractiveTriage.chooseGenerator(
            for: Self.law(for: method), typeName: "Int"
        ))
        #expect(argument != receiver)
    }

    /// With no scan, a project type has no generator, so the oracle declines and names it.
    @Test func anUnscannedProjectTypeIsDeclinedAsAGenerator() {
        let method = Self.summary(
            name: "scaled", owner: "Ruler", parameters: [Self.parameter(nil, "length", "Int")], isStatic: false
        )
        let outcome = SwiftInferCommand.Discover.referenceOracleOutcome(
            for: method, advisory: Self.fallback, suggestions: [Self.law(for: method)], context: .unscanned
        )
        #expect(outcome == .declined(
            "no generator derives for `Ruler`, so the oracle cannot draw its receiver — supply `static func gen()` "
                + "on `Ruler`, then re-run discover"
        ))
    }
}
