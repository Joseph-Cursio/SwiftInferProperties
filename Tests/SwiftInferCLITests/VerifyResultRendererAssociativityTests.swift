import Foundation
import Testing

@testable import SwiftInferCLI

// V1.46.C — VerifyResultRenderer associativity-template tests. Split
// from VerifyResultRendererTests.swift to keep both files under the
// type-body-length cap.

@Suite("VerifyResultRenderer — V1.46.C associativity template phrasing")
struct VerifyResultRendererAssociativityTests {

    private static let intContext = VerifyResultRenderer.Context(
        templateName: "associativity",
        forwardName: "Int.distance",
        inverseName: "Int.distance",
        carrierType: "Int"
    )

    private static let complexContext = VerifyResultRenderer.Context(
        templateName: "associativity",
        forwardName: "Complex._relaxedMul",
        inverseName: "Complex._relaxedMul",
        carrierType: "Complex<Double>"
    )

    @Test("associativity + defaultFails renders f(f(a, b), c) / f(a, f(b, c)) lines")
    func rendersAssociativityDefaultFails() {
        let rendered = VerifyResultRenderer.render(
            .defaultFails(
                trial: 0,
                input: "(5, 2, 3)",
                forwardResult: "6",
                inverseResult: "-4"
            ),
            context: Self.intContext
        )
        // Subject line uses "associativity on f", not commutativity/round-trip.
        #expect(rendered.contains("associativity on Int.distance over Int"))
        #expect(!rendered.contains("commutativity"))
        #expect(!rendered.contains("round-trip"))
        // Value lines reference the nested left/right association.
        #expect(rendered.contains("Int.distance(Int.distance(a, b), c) "))
        #expect(rendered.contains("Int.distance(a, Int.distance(b, c))"))
        // Expected line uses f(a, f(b, c)) as the right-assoc target.
        #expect(rendered.contains("expected ≈ Int.distance(a, Int.distance(b, c))"))
    }

    @Test("associativity + bothPass renders 'associativity on f' subject + Int sentinel")
    func rendersAssociativityBothPassIntSentinel() {
        let rendered = VerifyResultRenderer.render(
            .bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0),
            context: Self.intContext
        )
        #expect(rendered.contains("✓ verify holds (strong)"))
        #expect(rendered.contains("associativity on Int.distance over Int"))
        // Int carrier sentinel — edge pass not applicable.
        #expect(rendered.contains("(integer carrier — edge pass not applicable)"))
    }

    @Test("associativity + bothPass renders curated-edge-cases-sampled line for Complex")
    func rendersAssociativityBothPassComplexCuratedCount() {
        let rendered = VerifyResultRenderer.render(
            .bothPass(defaultTrials: 100, edgeTrials: 100, edgeSampled: 7),
            context: Self.complexContext
        )
        #expect(rendered.contains("associativity on Complex._relaxedMul over Complex<Double>"))
        // 7 / 12 curated edge cases sampled (per V1.43 phrasing).
        #expect(rendered.contains("(7 / 12 curated edge cases sampled)"))
    }

    @Test("associativity + edgeCaseAdvisory renders nested-assoc lines + edge tag")
    func rendersAssociativityEdgeAdvisory() {
        let rendered = VerifyResultRenderer.render(
            .edgeCaseAdvisory(
                defaultTrials: 100,
                edge: EdgeCaseDetail(
                    trial: 5,
                    input: "(Complex(nan, 0.0), Complex(1, 2), Complex(3, 4))",
                    forward: "Complex(nan, nan)",
                    inverse: "Complex(nan, nan)",
                    caseIndex: 1
                )
            ),
            context: Self.complexContext
        )
        #expect(rendered.contains("⚠ verify holds for finite domain"))
        #expect(rendered.contains("associativity on Complex._relaxedMul"))
        #expect(rendered.contains("edge case #1 (Complex(NaN, 0))"))
        // Two value lines, nested-assoc shape.
        #expect(rendered.contains("Complex._relaxedMul(Complex._relaxedMul(a, b), c) "))
        #expect(rendered.contains("Complex._relaxedMul(a, Complex._relaxedMul(b, c))"))
        #expect(rendered.contains("expected ≈ Complex._relaxedMul(a, Complex._relaxedMul(b, c))"))
    }

    @Test("associativity + error renders the error reason verbatim")
    func rendersAssociativityError() {
        let rendered = VerifyResultRenderer.render(
            .error(reason: "build failed: missing dependency"),
            context: Self.intContext
        )
        #expect(rendered.contains("build failed: missing dependency"))
    }
}
