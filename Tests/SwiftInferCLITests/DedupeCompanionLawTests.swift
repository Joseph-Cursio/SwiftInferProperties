import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// #711 — the companion-law channel's pieces, without a build: the emitted text, the parser,
/// scoring, accept-check and the rendering. `VerifyPipelineDedupeCountLawsTests` builds and runs it.
@Suite("Verify — #671's count laws as companions")
struct DedupeCompanionLawTests {

    private static func stub(_ body: DedupeBody?) throws -> String {
        try StrategistDispatchEmitter.emit(
            StrategistDispatchEmitter.Inputs(
                carrier: "[Int]", typeShape: nil, template: "idempotence", functionCalls: ["E.dedupe"],
                seedHex: .init(stateA: 1, stateB: 2, stateC: 3, stateD: 4), trialBudget: .small,
                dedupeBody: body
            )
        )
    }

    private static func output(_ stdout: String, exit: Int32 = 0) -> VerifierSubprocess.Output {
        VerifierSubprocess.Output(exitCode: exit, stdout: stdout, stderr: "")
    }

    // MARK: - Emission

    @Test("the companions run last, after both of idempotence's passes, on their own stream, never exiting")
    func emittedLastOnOwnStream() throws {
        let text = try Self.stub(DedupeBody(route: .set))
        let edge = try #require(text.range(of: "print(\"VERIFY_EDGE_RESULT: PASS\")", options: .backwards))
        let begin = try #require(text.range(of: "print(\"VERIFY_DEFAULT_LAW_C1_BEGIN\")"))
        let finalExit = try #require(text.range(of: "exit(0)", options: .backwards))
        #expect(edge.upperBound < begin.lowerBound, "after the edge pass's verdict")
        #expect(begin.upperBound < finalExit.lowerBound, "before the stub's last exit")
        #expect(text.components(separatedBy: "VERIFY_DEFAULT_LAW_C1_BEGIN").count == 2, "once, not per pass")
        #expect(!text.contains("VERIFY_EDGE_LAW_"), "never inside the edge pass")
        #expect(text.contains("var companionRng = Xoshiro(seed: seedTuple)"))
        let companions = String(text[begin.lowerBound ..< finalExit.lowerBound])
        #expect(!companions.contains("exit("), "a companion never decides the exit code")
        #expect(companions.contains("if doubled != once {"), "keep-first: C2 as equality")
    }

    @Test("the dictionary route's C2 compares counts; a row with no route emits no companions")
    func routeShapesTheLaws() throws {
        #expect(try Self.stub(DedupeBody(route: .dictionary)).contains("if doubled.count != once.count {"))
        #expect(try !Self.stub(nil).contains("VERIFY_DEFAULT_LAW_"))
    }

    @Test("a row with no route emits exactly what it did before the companions existed")
    func noRouteIsUnchanged() throws {
        let plain = try Self.stub(nil)
        #expect(!plain.contains("companionRng"))
        #expect(!plain.contains("\n\n\n"))
        #expect(plain.contains("if onceResult != twiceResult {"))
        #expect(plain.contains("if collisionTwice != collisionOnce {"))
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
        """))
        #expect(laws == [
            CompanionLawOutcome(law: "C1", status: .held),
            CompanionLawOutcome(law: "C2", status: .failed, trial: 7, input: "[3]", output: "[3, 3] vs [3]"),
        ])
        #expect(laws.refutation?.law == "C2")
        let trapped = VerifyResultParser.companionLaws(Self.output("VERIFY_DEFAULT_LAW_C1_BEGIN", exit: 133))
        #expect(trapped == [CompanionLawOutcome(law: "C1", status: .trapped)])
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

    /// #734's second review: a trap in a companion that ran inside the edge pass turned
    /// idempotence's PASS + PASS into `.error`. The companions now run after both passes, and a
    /// trap there keeps the verdict they could not have changed.
    @Test("a trap inside a companion, after both PASS markers, keeps idempotence's bothPass")
    func trapAfterBothPassesKeepsVerdict() {
        let output = Self.output("""
        VERIFY_DEFAULT_RESULT: PASS
        VERIFY_DEFAULT_TRIALS: 100
        VERIFY_EDGE_RESULT: PASS
        VERIFY_EDGE_TRIALS: 40
        VERIFY_EDGE_SAMPLED: 6
        VERIFY_DEFAULT_LAW_C1_BEGIN
        VERIFY_DEFAULT_LAW_C1_RESULT: PASS
        VERIFY_DEFAULT_LAW_C2_BEGIN
        """, exit: 133)
        guard case let .bothPass(defaultTrials, edgeTrials, edgeSampled) = VerifyResultParser.parse(output) else {
            Issue.record("a companion trap moved the verdict: \(VerifyResultParser.parse(output))")
            return
        }
        #expect(defaultTrials == 100)
        #expect(edgeTrials == 40)
        #expect(edgeSampled == 6)
        #expect(VerifyResultParser.companionLaws(output).refutation?.status == .trapped)
    }

    @Test("a trap with no companion running is still an error")
    func trapOutsideACompanionIsAnError() {
        let output = Self.output("VERIFY_DEFAULT_RESULT: PASS\nVERIFY_EDGE_RESULT: PASS\n", exit: 133)
        guard case .error = VerifyResultParser.parse(output) else {
            Issue.record("expected .error; got \(VerifyResultParser.parse(output))")
            return
        }
    }

    // MARK: - Accept-check and rendering

    @Test("accept-check reports a binding companion failure as a regression")
    func acceptCheckNowFails() {
        let failing = SwiftInferCommand.Verify.VerifyRun(
            outcome: .bothPass(defaultTrials: 100, edgeTrials: 100, edgeSampled: 0),
            rendered: "",
            companionLaws: [CompanionLawOutcome(law: "C2", status: .failed)]
        )
        let check = SwiftInferCommand.AcceptCheck.classify(run: failing)
        #expect(check.kind == .nowFails)
        #expect(check.detail == "companion law C2 failed")
        let holding = SwiftInferCommand.Verify.VerifyRun(
            outcome: .bothPass(defaultTrials: 100, edgeTrials: 100, edgeSampled: 0), rendered: ""
        )
        #expect(SwiftInferCommand.AcceptCheck.classify(run: holding).kind == .stillPasses)
    }

    @Test("the accepted route wins in accept-check, and only on idempotence")
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
        #expect(
            SwiftInferCommand.Verify.withAcceptedRoute(rescanned, accepted).dedupeBody == accepted,
            "the accepted stub's laws win: keep-first C2 is `==`, which a hash-order body fails"
        )
        #expect(SwiftInferCommand.Verify.withAcceptedRoute(rescanned, nil).dedupeBody?.route == .dictionary)
        var other = entry
        other.templateName = "monotonicity"
        #expect(SwiftInferCommand.Verify.withAcceptedRoute(other, accepted).dedupeBody == nil)
    }

    @Test("rendering adds one line per law, says what a refutation means, and nothing when none ran")
    func rendering() {
        #expect(VerifyResultRenderer.renderCompanions([]).isEmpty)
        let text = VerifyResultRenderer.renderCompanions([
            CompanionLawOutcome(law: "C1", status: .held),
            CompanionLawOutcome(law: "C2", status: .failed, trial: 2, input: "[1]"),
        ])
        #expect(text.contains("companion law: C1 held: a singleton survives"))
        #expect(text.contains("companion law: C2 FAILED at trial 2: "))
        #expect(text.contains("→ not Verified"))
    }
}
