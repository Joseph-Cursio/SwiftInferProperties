import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// PROTOTYPE — routing/gating/emit logic for the `@Observable` execution-backed
/// verify pipeline (Observable Carrier milestone, Slice 1). The build+run step
/// is injected, so these tests cover the decision logic without a real
/// `swift build`.
@Suite("ViewModelVerifyInteractionPipeline (prototype)")
struct ViewModelVerifyInteractionPipelineTests {

    private static let workdir = URL(fileURLWithPath: "/tmp/vm-verify-unit")

    private static func vmAction(
        _ name: String,
        _ parameters: [ViewModelActionParameter] = [],
        isAsync: Bool = false
    ) -> ViewModelAction {
        ViewModelAction(
            name: name,
            parameterTypes: parameters.map(\.typeText),
            firstParameterLabel: parameters.first?.label,
            parameters: parameters,
            isAsync: isAsync,
            isThrows: false,
            mutatesStateDirectly: true
        )
    }

    private static func candidate(
        typeName: String = "SelectionModel",
        actions: [ViewModelAction],
        constructibility: ViewModelConstructibility = .zeroArgument
    ) -> ViewModelCandidate {
        ViewModelCandidate(
            location: "\(typeName).swift:1",
            typeName: typeName,
            observability: .observableMacro,
            stateFields: [.init(name: "selectedIDs", typeText: "Set<UUID>", isMutable: true)],
            actions: actions,
            constructibility: constructibility
        )
    }

    /// A runner that fails the test if it is ever invoked (gate cases must
    /// short-circuit before build+run).
    private static let unreachableRunner: ViewModelVerifyInteractionPipeline.VerifyRunner = { _, _, _ in
        .error(reason: "RUNNER_SHOULD_NOT_BE_CALLED")
    }

    /// A runner returning a canned outcome, and asserting the emitted stub is
    /// the M1′ shape.
    private static func fakeRunner(
        returning outcome: VerifyOutcome
    ) -> ViewModelVerifyInteractionPipeline.VerifyRunner {
        { stub, _, _ in
            #expect(stub.contains("enum SelectionModelAction"))
            #expect(stub.contains("func drive(_ model: SelectionModel,"))
            #expect(stub.contains("ActionSequenceFactory.actionSequence("))
            return outcome
        }
    }

    @Test("clean nullary candidate runs and reports the runner's outcome")
    func runsAndReportsOutcome() {
        let result = ViewModelVerifyInteractionPipeline.verify(
            candidate: Self.candidate(actions: [Self.vmAction("selectAll"), Self.vmAction("deselectAll")]),
            predicate: "probe.selectedIDs.isEmpty || true",
            sourceFiles: [],
            workdir: Self.workdir,
            runner: Self.fakeRunner(
                returning: .bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0)
            )
        )
        guard case .ran(.bothPass) = result else {
            Issue.record("expected .ran(.bothPass), got \(result)")
            return
        }
    }

    @Test("a failing verifier surfaces defaultFails")
    func surfacesFailure() {
        let failure = VerifyOutcome.defaultFails(
            trial: 1, input: "sequence", forwardResult: "", inverseResult: "",
            shrunk: nil, shrinkSteps: 0
        )
        let result = ViewModelVerifyInteractionPipeline.verify(
            candidate: Self.candidate(actions: [Self.vmAction("selectAll")]),
            predicate: "false",
            sourceFiles: [],
            workdir: Self.workdir,
            runner: Self.fakeRunner(returning: failure)
        )
        guard case .ran(.defaultFails) = result else {
            Issue.record("expected .ran(.defaultFails), got \(result)")
            return
        }
    }

    @Test("non-zero-arg-constructible candidate is skipped before build+run")
    func skipsOnConstructibilityGate() {
        let result = ViewModelVerifyInteractionPipeline.verify(
            candidate: Self.candidate(
                actions: [Self.vmAction("selectAll")],
                constructibility: .requiresArguments(["service"])
            ),
            predicate: "true",
            sourceFiles: [],
            workdir: Self.workdir,
            runner: Self.unreachableRunner
        )
        guard case let .skipped(reason) = result else {
            Issue.record("expected .skipped, got \(result)")
            return
        }
        #expect(reason.contains("not zero-arg constructible"))
        #expect(reason.contains("service"))
    }

    @Test("no constructible action is skipped before build+run")
    func skipsOnEmitFailure() {
        // Only an async method → the enum surface is empty → emit throws.
        let result = ViewModelVerifyInteractionPipeline.verify(
            candidate: Self.candidate(actions: [Self.vmAction("load", isAsync: true)]),
            predicate: "true",
            sourceFiles: [],
            workdir: Self.workdir,
            runner: Self.unreachableRunner
        )
        guard case let .skipped(reason) = result else {
            Issue.record("expected .skipped, got \(result)")
            return
        }
        #expect(reason.contains("no liftable"))
    }
}
