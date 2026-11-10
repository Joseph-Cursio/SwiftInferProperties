import Foundation
import Testing

@testable import SwiftInferCLI

@Suite("VerifyResultRenderer — V1.48.D monotonicity phrasing")
struct VerifyResultRendererMonotonicityTests {

    private static let context = VerifyResultRenderer.Context(
        templateName: "monotonicity",
        forwardName: "Int.doubled",
        inverseName: "Int.doubled",
        carrierType: "Int"
    )

    @Test("subject line: 'monotonicity on f over T'")
    func subjectLine() {
        let rendered = VerifyResultRenderer.render(
            .bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0),
            context: Self.context
        )
        #expect(rendered.contains("monotonicity on Int.doubled over Int"))
    }

    @Test("defaultFails: emits f(a) and f(b) value lines + ≤ expected expression")
    func defaultFailsValueLines() {
        let rendered = VerifyResultRenderer.render(
            .defaultFails(
                trial: 0,
                input: "(3, 7)",
                forwardResult: "6",
                inverseResult: "5",  // pretend non-monotone
                shrunk: nil,
                shrinkSteps: 0
            ),
            context: Self.context
        )
        #expect(rendered.contains("Int.doubled(a) "))
        #expect(rendered.contains("Int.doubled(b)"))
        #expect(rendered.contains("expected ≈ f(a) ≤ f(b) when a ≤ b"))
    }

    @Test("error case renders the reason verbatim")
    func errorCase() {
        let rendered = VerifyResultRenderer.render(
            .error(reason: "build failed: missing dependency"),
            context: Self.context
        )
        #expect(rendered.contains("build failed: missing dependency"))
    }
}
