import Foundation
import Testing

@testable import SwiftInferCLI

// VerifyResultRenderer involution-template tests. Involution (`f(f(x)) == x`)
// previously fell through `renderShape`'s `default` arm and rendered with
// round-trip phrasing ("round-trip f/f over T"); it now has its own phrasing.

@Suite("VerifyResultRenderer — involution template phrasing")
struct VerifyResultRendererInvolutionTests {

    private static let context = VerifyResultRenderer.Context(
        templateName: "involution",
        forwardName: "Laws.negated",
        inverseName: "Laws.negated",
        carrierType: "Laws"
    )

    @Test("involution + defaultFails renders f(input) / f(f(input)) lines, not round-trip")
    func rendersInvolutionDefaultFails() {
        let rendered = VerifyResultRenderer.render(
            .defaultFails(
                trial: 0,
                input: "3",
                forwardResult: "-3",
                inverseResult: "3",
                shrunk: nil,
                shrinkSteps: 0
            ),
            context: Self.context
        )
        // Subject line is involution-specific, no longer the round-trip default.
        #expect(rendered.contains("involution on Laws.negated over Laws"))
        #expect(rendered.contains("round-trip") == false)
        // Value lines: f(input) then f(f(input)); expected is the original input.
        #expect(rendered.contains("Laws.negated(input) "))
        #expect(rendered.contains("Laws.negated(Laws.negated(input))"))
        #expect(rendered.contains("expected ≈ input"))
    }

    @Test("involution + bothPass renders 'involution on f' subject")
    func rendersInvolutionBothPass() {
        let rendered = VerifyResultRenderer.render(
            .bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0),
            context: Self.context
        )
        #expect(rendered.contains("involution on Laws.negated over Laws"))
        #expect(rendered.contains("round-trip") == false)
    }
}
