import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

// V2.0 M3.E — render-side tests for VerifyInteractionPipeline:
// outcome rendering + workdir-segment filename safety. Split out
// of VerifyInteractionPipelineTests so the main suite stays under
// SwiftLint's type_body_length cap as the M3.E surface accreted.

@Suite("VerifyInteractionPipeline — V2.0 M3.E rendering + workdir helpers")
struct VerifyInteractionPipelineRenderTests {

    private func freeCandidate(
        functionName: String = "reduce",
        signatureShape: ReducerSignatureShape = .stateActionReturnsState,
        stateTypeName: String = "S",
        actionTypeName: String = "A",
        carrierKind: ReducerCarrierKind = .elmStyle,
        purity: ReducerPurity = .pure
    ) -> ReducerCandidate {
        ReducerCandidate(
            location: "F.swift:1",
            enclosingTypeName: nil,
            functionName: functionName,
            signatureShape: signatureShape,
            stateTypeName: stateTypeName,
            actionTypeName: actionTypeName,
            carrierKind: carrierKind,
            purity: purity
        )
    }

    @Test("renderOutcome includes candidate metadata + the outcome rawValue")
    func renderOutcomeShape() {
        let result = InteractionVerifyOutcomeParser.Result(
            outcome: .measuredBothPass,
            totalRuns: 1_024,
            cleanRuns: 1_024,
            detail: "totalRuns=1024 clean=1024"
        )
        let rendered = VerifyInteractionPipeline.renderOutcome(
            candidate: freeCandidate(),
            result: result
        )
        #expect(rendered.contains("Reducer: reduce"))
        #expect(rendered.contains("Outcome: measured-bothPass"))
        #expect(rendered.contains("Total runs: 1024"))
        #expect(rendered.contains("Clean runs: 1024"))
    }

    @Test("renderOutcome shows architectural-coverage-pending detail when build failed")
    func renderOutcomeBuildFailureDetail() {
        let result = InteractionVerifyOutcomeParser.Result(
            outcome: .architecturalCoveragePending,
            detail: "swift build failed with exit code 1"
        )
        let rendered = VerifyInteractionPipeline.renderOutcome(
            candidate: freeCandidate(),
            result: result
        )
        #expect(rendered.contains("Outcome: architectural-coverage-pending"))
        #expect(rendered.contains("swift build failed"))
    }

    @Test("renderOutcome surfaces the trace path on defaultFails (M8.C)")
    func renderOutcomeShowsTracePath() {
        let result = InteractionVerifyOutcomeParser.Result(
            outcome: .measuredDefaultFails,
            detail: "verifier exited with code 134 — trap in reducer body"
        )
        let tracePath = URL(fileURLWithPath:
            "/tmp/MyPackage/Tests/Generated/SwiftInferTraces/reduce/trace-replay.swift"
        )
        let rendered = VerifyInteractionPipeline.renderOutcome(
            candidate: freeCandidate(),
            result: result,
            tracePath: tracePath
        )
        #expect(rendered.contains("Trace: "))
        #expect(rendered.contains("Tests/Generated/SwiftInferTraces/reduce/trace-replay.swift"))
    }

    @Test("renderOutcome omits the Trace line when no trace path is supplied")
    func renderOutcomeOmitsTraceWhenNil() {
        let result = InteractionVerifyOutcomeParser.Result(
            outcome: .measuredBothPass,
            totalRuns: 1_024,
            cleanRuns: 1_024,
            detail: nil
        )
        let rendered = VerifyInteractionPipeline.renderOutcome(
            candidate: freeCandidate(),
            result: result,
            tracePath: nil
        )
        #expect(!rendered.contains("Trace:"))
    }

    @Test("renderOutcome surfaces the candidate's purity classification (M8.B)")
    func renderOutcomeShowsPurity() {
        let result = InteractionVerifyOutcomeParser.Result(
            outcome: .measuredBothPass,
            totalRuns: 1_024,
            cleanRuns: 1_024,
            detail: nil
        )
        let pureRender = VerifyInteractionPipeline.renderOutcome(
            candidate: freeCandidate(purity: .pure),
            result: result
        )
        #expect(pureRender.contains("Purity: pure"))
        let effectRender = VerifyInteractionPipeline.renderOutcome(
            candidate: freeCandidate(purity: .effectBearing),
            result: result
        )
        #expect(effectRender.contains("Purity: effect-bearing"))
    }

    @Test("workdirSegment is filename-safe: dots become underscores")
    func workdirSegmentReplacesDots() {
        let methodCandidate = ReducerCandidate(
            location: "F.swift:1",
            enclosingTypeName: "Inbox",
            functionName: "body",
            signatureShape: .stateActionReturnsState,
            stateTypeName: "Inbox.State",
            actionTypeName: "Inbox.Action"
        )
        #expect(VerifyInteractionPipeline.workdirSegment(for: methodCandidate) == "Inbox_body")
        #expect(VerifyInteractionPipeline.workdirSegment(for: freeCandidate()) == "reduce")
    }
}
