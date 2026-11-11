import Foundation
import Testing

@testable import SwiftInferCLI

// MARK: - Double-carrier real-axis curated rendering

extension VerifyResultRendererTests {

    @Test("Double + bothPass renders 'N / 9 curated edge cases sampled'")
    func rendersDoubleCarrierBothPass() {
        let rendered = VerifyResultRenderer.render(
            .bothPass(defaultTrials: 100, edgeTrials: 100, edgeSampled: 6),
            context: Self.doubleContext
        )
        #expect(rendered.contains("(6 / 9 curated edge cases sampled)"))
    }

    @Test("Double + edgeCaseAdvisory index=0 renders 'edge case #0 (NaN)'")
    func rendersDoubleCarrierEdgeCaseAdvisoryNaN() {
        let rendered = VerifyResultRenderer.render(
            .edgeCaseAdvisory(
                defaultTrials: 100,
                edge: EdgeCaseDetail(
                    trial: 7,
                    input: "nan",
                    forward: "nan",
                    inverse: "nan",
                    caseIndex: 0
                )
            ),
            context: Self.doubleContext
        )
        #expect(rendered.contains("edge case #0 (NaN)"))
        // The 12-entry Complex labels must NOT leak into Double rendering.
        #expect(!rendered.contains("Complex(NaN"))
    }

    @Test("Double + edgeCaseAdvisory renders the real-axis label for a non-NaN index")
    func rendersDoubleCarrierEdgeCaseAdvisoryInfinity() {
        let rendered = VerifyResultRenderer.render(
            .edgeCaseAdvisory(
                defaultTrials: 100,
                edge: EdgeCaseDetail(
                    trial: 3,
                    input: "inf",
                    forward: "inf",
                    inverse: "inf",
                    caseIndex: 1
                )
            ),
            context: Self.doubleContext
        )
        #expect(rendered.contains("edge case #1 (+Infinity)"))
    }
}
