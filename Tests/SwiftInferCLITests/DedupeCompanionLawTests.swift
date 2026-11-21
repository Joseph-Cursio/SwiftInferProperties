import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// #711 — the companion-law channel's pieces, without a build: the emitted text, the parser,
/// scoring, accept-check and the rendering. `VerifyPipelineDedupeCountLawsTests` builds and runs it.
@Suite("Verify — #671's count laws as companions")
struct DedupeCompanionLawTests {

    private static func pass(_ body: DedupeBody?) throws -> String {
        try StrategistDispatchEmitter.defaultPassSection(
            inputs: StrategistDispatchEmitter.Inputs(
                carrier: "[Int]", typeShape: nil, template: "idempotence", functionCalls: ["E.dedupe"],
                seedHex: .init(stateA: 1, stateB: 2, stateC: 3, stateD: 4), trialBudget: .small,
                dedupeBody: body
            ),
            recipe: StrategistDispatchEmitter.GeneratorRecipe(
                expression: "Gen<Int>.int().array(of: 0...8)", carrierTypeName: "[Int]", imports: []
            )
        )
    }

    private static func output(_ stdout: String, exit: Int32 = 0) -> VerifierSubprocess.Output {
        VerifierSubprocess.Output(exitCode: exit, stdout: stdout, stderr: "")
    }

    // MARK: - Emission

    @Test("the companions run after idempotence's PASS, on their own stream, and never exit")
    func emittedAfterPassOnOwnStream() throws {
        let text = try Self.pass(DedupeBody(route: .set))
        let pass = try #require(text.range(of: "print(\"VERIFY_DEFAULT_RESULT: PASS\")"))
        let begin = try #require(text.range(of: "print(\"VERIFY_DEFAULT_LAW_C1_BEGIN\")"))
        #expect(pass.upperBound < begin.lowerBound)
        #expect(text.contains("var companionRng = Xoshiro(seed: seedTuple)"))
        #expect(text.contains("defaultGenerator.run(using: &companionRng)"))
        let companions = String(text[begin.lowerBound...])
        #expect(!companions.contains("exit("), "a companion never decides the exit code")
        #expect(companions.contains("if doubled != once {"), "keep-first: C2 as equality")
    }

    @Test("the dictionary route's C2 compares counts; a row with no route emits no companions")
    func routeShapesTheLaws() throws {
        #expect(try Self.pass(DedupeBody(route: .dictionary)).contains("if doubled.count != once.count {"))
        #expect(try !Self.pass(nil).contains("VERIFY_DEFAULT_LAW_"))
    }

    // MARK: - Parsing

    @Test("held, failed with its detail, trapped, and not run are four different readings")
    func parsesEachStatus() {
        let laws = VerifyResultParser.companionLaws(Self.output("""
        VERIFY_DEFAULT_RESULT: PASS
        VERIFY_DEFAULT_LAW_C1_BEGIN
        VERIFY_DEFAULT_LAW_C1_RESULT: PASS
        VERIFY_DEFAULT_LAW_C2_BEGIN
        VERIFY_DEFAULT_LAW_C2_RESULT: FAIL
        VERIFY_DEFAULT_LAW_C2_TRIAL: 7
        VERIFY_DEFAULT_LAW_C2_INPUT: [3]
        VERIFY_DEFAULT_LAW_C2_OUTPUT: [3, 3] vs [3]
        VERIFY_EDGE_RESULT: PASS
        VERIFY_EDGE_LAW_C1_BEGIN
        """, exit: 139))
        #expect(laws == [
            CompanionLawOutcome(law: "C1", pass: .default, status: .held),
            CompanionLawOutcome(
                law: "C2", pass: .default, status: .failed, trial: 7, input: "[3]", output: "[3, 3] vs [3]"
            ),
            CompanionLawOutcome(law: "C1", pass: .edge, status: .trapped),
        ])
        #expect(laws.refutation?.law == "C2")
    }

    @Test("a companion failure leaves idempotence's verdict a pass, and nothing ran means nothing")
    func verdictIsUnmoved() {
        let stdout = """
        VERIFY_DEFAULT_RESULT: PASS
        VERIFY_DEFAULT_TRIALS: 100
        VERIFY_DEFAULT_LAW_C1_BEGIN
        VERIFY_DEFAULT_LAW_C1_RESULT: FAIL
        VERIFY_EDGE_RESULT: PASS
        VERIFY_EDGE_TRIALS: 100
        """
        guard case .bothPass = VerifyResultParser.parse(Self.output(stdout)) else {
            Issue.record("a companion failure moved the verdict")
            return
        }
        #expect(VerifyResultParser.companionLaws(Self.output("VERIFY_DEFAULT_RESULT: FAIL")).isEmpty)
        #expect(VerifyResultParser.recordedCompanionLaws(Self.output("VERIFY_DEFAULT_RESULT: PASS")) == nil)
    }

    @Test("an edge-pass failure is advisory and refutes nothing")
    func edgeIsAdvisory() {
        let edge = CompanionLawOutcome(law: "C1", pass: .edge, status: .failed)
        #expect(!edge.refutes)
        #expect([edge].refutation == nil)
        #expect(CompanionLawOutcome(law: "C1", pass: .default, status: .trapped).refutes)
    }

    // MARK: - Accept-check and rendering

    @Test("accept-check reports a binding companion failure as a regression")
    func acceptCheckNowFails() {
        let failing = SwiftInferCommand.Verify.VerifyRun(
            outcome: .bothPass(defaultTrials: 100, edgeTrials: 100, edgeSampled: 0),
            rendered: "",
            companionLaws: [CompanionLawOutcome(law: "C2", pass: .default, status: .failed)]
        )
        let check = SwiftInferCommand.AcceptCheck.classify(run: failing)
        #expect(check.kind == .nowFails)
        #expect(check.detail == "companion law C2 failed")
        let holding = SwiftInferCommand.Verify.VerifyRun(
            outcome: .bothPass(defaultTrials: 100, edgeTrials: 100, edgeSampled: 0), rendered: ""
        )
        #expect(SwiftInferCommand.AcceptCheck.classify(run: holding).kind == .stillPasses)
    }

    @Test("the accepted route is used only when a re-scan finds none, and only for idempotence")
    func acceptedRoute() {
        let entry = SemanticIndexEntry(
            identityHash: "0x1", templateName: "idempotence", score: 45, tier: "Likely",
            primaryFunctionName: "dedupe(_:)", location: "D.swift:1", firstSeenAt: "t", lastSeenAt: "t"
        )
        let accepted = DedupeBody(route: .set)
        #expect(SwiftInferCommand.Verify.withAcceptedRoute(entry, accepted).dedupeBody == accepted)
        #expect(SwiftInferCommand.Verify.withAcceptedRoute(entry, nil).dedupeBody == nil)
        var rescanned = entry
        rescanned.dedupeBody = DedupeBody(route: .dictionary)
        #expect(SwiftInferCommand.Verify.withAcceptedRoute(rescanned, accepted).dedupeBody?.route == .dictionary)
        var other = entry
        other.templateName = "monotonicity"
        #expect(SwiftInferCommand.Verify.withAcceptedRoute(other, accepted).dedupeBody == nil)
    }

    @Test("rendering adds one line per law, says what a refutation means, and nothing when none ran")
    func rendering() {
        #expect(VerifyResultRenderer.renderCompanions([]).isEmpty)
        let text = VerifyResultRenderer.renderCompanions([
            CompanionLawOutcome(law: "C1", pass: .default, status: .held),
            CompanionLawOutcome(law: "C2", pass: .default, status: .failed, trial: 2, input: "[1]"),
        ])
        #expect(text.contains("companion law: C1 held on the default pass"))
        #expect(text.contains("companion law: C2 FAILED on the default pass at trial 2"))
        #expect(text.contains("→ not Verified"))
    }
}
