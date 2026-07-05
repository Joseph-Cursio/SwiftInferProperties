import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// PROTOTYPE — the `@Observable` verify survey: resolve every supported family
/// predicate per candidate, verify via the M1′ pipeline (injected runner), and
/// render verdicts. (Observable Carrier milestone, Slice 4.)
@Suite("ViewModelVerifyInteractionSurvey (prototype)")
struct ViewModelVerifyInteractionSurveyTests {

    private static let workdir = URL(fileURLWithPath: "/tmp/vm-survey-unit")

    /// A value-membership refint candidate: `selected: Set<Int>` over
    /// `items: [Int]` — the shape `ViewModelRefintResolver` matches.
    private static func refintCandidate(_ typeName: String) -> ViewModelCandidate {
        ViewModelCandidate(
            location: "\(typeName).swift:1",
            typeName: typeName,
            observability: .observableMacro,
            stateFields: [
                .init(name: "items", typeText: "[Int]", isMutable: true),
                .init(name: "selected", typeText: "Set<Int>", isMutable: true)
            ],
            actions: [
                ViewModelAction(
                    name: "selectAll", parameterTypes: [], parameters: [],
                    isAsync: false, isThrows: false, mutatesStateDirectly: true
                )
            ]
        )
    }

    @Test("verdict maps outcomes to promotion labels")
    func verdictLabels() {
        typealias Step = ViewModelVerifyInteractionPipeline.StepResult
        #expect(ViewModelVerifyInteractionSurvey.verdict(
            .ran(.bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0))
        ) == "VERIFIED (100 trials)")
        #expect(ViewModelVerifyInteractionSurvey.verdict(
            .ran(.defaultFails(.init(trial: 3, input: "s", forwardResult: "", inverseResult: "", shrink: nil)))
        ) == "REFUTED (trial 3)")
        let skippedLabel = ViewModelVerifyInteractionSurvey.verdict(
            Step.skipped(reason: "requires args")
        )
        #expect(skippedLabel.hasPrefix("skipped"))
    }

    @Test("surveys every resolvable candidate × family, VERIFIED on a passing runner")
    func surveysAndVerifies() {
        let runner: ViewModelVerifyInteractionPipeline.VerifyRunner = { _, _, _ in
            .bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0)
        }
        let entries = ViewModelVerifyInteractionSurvey.run(
            candidates: [Self.refintCandidate("BModel"), Self.refintCandidate("AModel")],
            sourceFiles: [],
            workdir: Self.workdir,
            runner: runner
        )
        // At least the referential-integrity family resolves for each candidate.
        #expect(entries.contains { $0.typeName == "AModel" && $0.family == "referential-integrity" })
        #expect(entries.contains { $0.typeName == "BModel" && $0.family == "referential-integrity" })
        // Deterministic order: candidate name ascending.
        #expect(entries.first?.typeName == "AModel")

        let render = ViewModelVerifyInteractionSurvey.render(target: "App", entries: entries)
        #expect(render.contains("ViewModel interaction verify — App"))
        #expect(render.contains("AModel.referential-integrity: VERIFIED (100 trials)"))
    }

    @Test("empty survey renders the no-carriers note")
    func emptyRender() {
        let render = ViewModelVerifyInteractionSurvey.render(target: "App", entries: [])
        #expect(render.contains("no verifiable @Observable carriers"))
    }
}
