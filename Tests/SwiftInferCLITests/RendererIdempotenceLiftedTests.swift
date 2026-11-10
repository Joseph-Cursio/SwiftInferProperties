import Foundation
import Testing

@testable import SwiftInferCLI

// V1.48.G — VerifyResultRenderer tests for the 3 new RenderShape
// cases added in V1.48.D (idempotence-lifted, dual-style-consistency,
// monotonicity).

@Suite("VerifyResultRenderer — V1.48.D idempotence-lifted phrasing")
struct RendererIdempotenceLiftedTests {

    private static let context = VerifyResultRenderer.Context(
        templateName: "idempotence-lifted",
        forwardName: "Array.sorted",
        inverseName: "Array.sorted",
        carrierType: "Int"
    )

    @Test("subject line: 'idempotence-lifted on f over [T]'")
    func subjectLineIncludesLiftedCarrier() {
        let rendered = VerifyResultRenderer.render(
            .bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0),
            context: Self.context
        )
        #expect(rendered.contains("idempotence-lifted on Array.sorted over [Int]"))
    }

    @Test("defaultFails: emits f(xs) and f(f(xs)) value lines")
    func defaultFailsValueLines() {
        let rendered = VerifyResultRenderer.render(
            .defaultFails(
                trial: 0,
                input: "[3, 1, 2]",
                forwardResult: "[1, 2, 3]",
                inverseResult: "[1, 2, 3, 4]"
            ),
            context: Self.context
        )
        #expect(rendered.contains("Array.sorted(xs) "))
        #expect(rendered.contains("Array.sorted(Array.sorted(xs))"))
        #expect(rendered.contains("expected ≈ Array.sorted(xs)"))
    }
}
