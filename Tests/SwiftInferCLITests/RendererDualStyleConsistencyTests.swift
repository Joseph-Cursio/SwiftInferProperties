import Foundation
import Testing

@testable import SwiftInferCLI

@Suite("VerifyResultRenderer — V1.48.D dual-style-consistency phrasing")
struct RendererDualStyleConsistencyTests {

    private static let context = VerifyResultRenderer.Context(
        templateName: "dual-style-consistency",
        forwardName: "Array.sorted",
        inverseName: "sort",
        carrierType: "Array"
    )

    @Test("subject line includes both styles")
    func subjectLineIncludesBothStyles() {
        let rendered = VerifyResultRenderer.render(
            .bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0),
            context: Self.context
        )
        #expect(rendered.contains("dual-style-consistency on Array.sorted/sort over Array"))
    }

    @Test("defaultFails: emits non-mut + mutating-copy-idiom lines")
    func defaultFailsValueLines() {
        let rendered = VerifyResultRenderer.render(
            .defaultFails(
                trial: 0,
                input: "[3, 1, 2]",
                forwardResult: "[1, 2, 3]",
                inverseResult: "[3, 1, 2]",
                shrunk: nil,
                shrinkSteps: 0
            ),
            context: Self.context
        )
        #expect(rendered.contains("Array.sorted(x) "))
        #expect(rendered.contains("var copy = x"))
        #expect(rendered.contains("copy.sort()"))
        #expect(rendered.contains("expected ≈ Array.sorted(x)"))
    }
}
