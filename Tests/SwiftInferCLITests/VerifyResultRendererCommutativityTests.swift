import Foundation
import Testing

@testable import SwiftInferCLI

// V1.45.C — VerifyResultRenderer commutativity-template tests. Split
// from VerifyResultRendererTests.swift to keep both files under the
// type-body-length cap.

@Suite("VerifyResultRenderer — V1.45.C commutativity template phrasing")
struct VerifyResultRendererCommutativityTests {

    private static let intContext = VerifyResultRenderer.Context(
        templateName: "commutativity",
        forwardName: "Int.binomial",
        inverseName: "Int.binomial",
        carrierType: "Int"
    )

    private static let complexContext = VerifyResultRenderer.Context(
        templateName: "commutativity",
        forwardName: "Complex.weird",
        inverseName: "Complex.weird",
        carrierType: "Complex<Double>"
    )

    @Test("commutativity + defaultFails renders f(lhs, rhs) / f(rhs, lhs) lines")
    func rendersCommutativityDefaultFails() {
        let rendered = VerifyResultRenderer.render(
            .defaultFails(
                trial: 0,
                input: "(5, 2)",
                forwardResult: "10",
                inverseResult: "0"
            ),
            context: Self.intContext
        )
        // Subject line uses "commutativity on f", not "round-trip f/g".
        #expect(rendered.contains("commutativity on Int.binomial over Int"))
        #expect(!rendered.contains("round-trip"))
        // Value lines reference the swapped pair order.
        #expect(rendered.contains("Int.binomial(lhs, rhs) "))
        #expect(rendered.contains("Int.binomial(rhs, lhs)"))
        // Expected line uses f(rhs, lhs) as the target.
        #expect(rendered.contains("expected ≈ Int.binomial(rhs, lhs)"))
    }

    @Test("commutativity + bothPass renders 'commutativity on f' subject")
    func rendersCommutativityBothPass() {
        let rendered = VerifyResultRenderer.render(
            .bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0),
            context: Self.intContext
        )
        #expect(rendered.contains("✓ verify holds (strong)"))
        #expect(rendered.contains("commutativity on Int.binomial over Int"))
        // Int carrier sentinel — edge pass not applicable.
        #expect(rendered.contains("(integer carrier — edge pass not applicable)"))
    }

    @Test("commutativity + edgeCaseAdvisory renders swapped-order lines + edge tag")
    func rendersCommutativityEdgeAdvisory() {
        let rendered = VerifyResultRenderer.render(
            .edgeCaseAdvisory(
                defaultTrials: 100,
                edgeTrial: 5,
                edgeInput: "(Complex(nan, 0.0), Complex(1, 2))",
                edgeForward: "Complex(...)",
                edgeInverse: "Complex(...)",
                edgeCaseIndex: 1
            ),
            context: Self.complexContext
        )
        #expect(rendered.contains("⚠ verify holds for finite domain"))
        #expect(rendered.contains("commutativity on Complex.weird"))
        #expect(rendered.contains("edge case #1 (Complex(NaN, 0))"))
        // Two value lines, swapped-order shape.
        #expect(rendered.contains("Complex.weird(lhs, rhs) "))
        #expect(rendered.contains("Complex.weird(rhs, lhs)"))
        #expect(rendered.contains("expected ≈ Complex.weird(rhs, lhs)"))
    }
}
