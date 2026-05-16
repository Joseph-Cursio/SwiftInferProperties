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
                inverseResult: "[3, 1, 2]"
            ),
            context: Self.context
        )
        #expect(rendered.contains("Array.sorted(x) "))
        #expect(rendered.contains("var copy = x"))
        #expect(rendered.contains("copy.sort()"))
        #expect(rendered.contains("expected ≈ Array.sorted(x)"))
    }
}

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
                inverseResult: "5"  // pretend non-monotone
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
