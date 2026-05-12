import Foundation
import Testing

@testable import SwiftInferCLI

// V1.43.D / V1.44.D — VerifyResultRenderer tests. Split out of
// VerifyResultTests.swift to keep both files within the file_length cap.

@Suite("VerifyResult — V1.43.D renderer (4-outcome two-pass shape)")
struct VerifyResultRendererTests {

    private static let canonicalContext = VerifyResultRenderer.Context(
        templateName: "round-trip",
        forwardName: "Complex.exp",
        inverseName: "Complex.log",
        carrierType: "Complex<Double>"
    )

    private static let idempotenceContext = VerifyResultRenderer.Context(
        templateName: "idempotence",
        forwardName: "Complex.normalize",
        inverseName: "Complex.normalize",
        carrierType: "Complex<Double>"
    )

    private static let intContext = VerifyResultRenderer.Context(
        templateName: "round-trip",
        forwardName: "Int.identity",
        inverseName: "Int.identity",
        carrierType: "Int"
    )

    private static let doubleContext = VerifyResultRenderer.Context(
        templateName: "round-trip",
        forwardName: "abs",
        inverseName: "abs",
        carrierType: "Double"
    )

    private static func output(
        exitCode: Int32,
        stdout: String,
        stderr: String = ""
    ) -> VerifierSubprocess.Output {
        VerifierSubprocess.Output(exitCode: exitCode, stdout: stdout, stderr: stderr)
    }

    @Test("bothPass renders ✓ strong header + per-pass counts + sampled line")
    func rendersBothPass() {
        let rendered = VerifyResultRenderer.render(
            .bothPass(defaultTrials: 100, edgeTrials: 100, edgeSampled: 12),
            context: Self.canonicalContext
        )
        #expect(rendered.contains("✓ verify holds (strong)"))
        #expect(rendered.contains("Complex.exp/Complex.log"))
        #expect(rendered.contains("Complex<Double>"))
        #expect(rendered.contains("100 default trials"))
        #expect(rendered.contains("100 edge-case-biased trials"))
        #expect(rendered.contains("12 / 12 curated edge cases sampled"))
    }

    @Test("bothPass with N=1 uses singular 'trial'")
    func rendersBothPassSingular() {
        let rendered = VerifyResultRenderer.render(
            .bothPass(defaultTrials: 1, edgeTrials: 1, edgeSampled: 0),
            context: Self.canonicalContext
        )
        #expect(rendered.contains("1 default trial "))
        #expect(rendered.contains("1 edge-case-biased trial,"))
        #expect(!rendered.contains("1 default trials"))
    }

    @Test("edgeCaseAdvisory with known index renders #N (label) tag")
    func rendersEdgeCaseAdvisoryKnownIndex() {
        let rendered = VerifyResultRenderer.render(
            .edgeCaseAdvisory(
                defaultTrials: 100,
                edgeTrial: 7,
                edgeInput: "Complex(nan, 0.0)",
                edgeForward: "Complex(nan, nan)",
                edgeInverse: "Complex(nan, nan)",
                edgeCaseIndex: 1
            ),
            context: Self.canonicalContext
        )
        #expect(rendered.hasPrefix("⚠ verify holds for finite domain"))
        #expect(rendered.contains("default pass 100/100"))
        #expect(rendered.contains("edge pass failed at trial 7"))
        #expect(rendered.contains("edge case #1 (Complex(NaN, 0))"))
        #expect(rendered.contains("Complex(nan, 0.0)"))
        #expect(rendered.contains("isApproximatelyEqual"))
    }

    @Test("edgeCaseAdvisory with index -1 falls back to non-curated phrasing")
    func rendersEdgeCaseAdvisoryUnknownIndex() {
        let rendered = VerifyResultRenderer.render(
            .edgeCaseAdvisory(
                defaultTrials: 100,
                edgeTrial: 3,
                edgeInput: "Complex(1.5, -2.5)",
                edgeForward: "Complex(3.0, -5.0)",
                edgeInverse: "Complex(0.0, 0.0)",
                edgeCaseIndex: -1
            ),
            context: Self.canonicalContext
        )
        #expect(rendered.contains("on a non-curated value"))
        #expect(!rendered.contains("edge case #"))
    }

    @Test("defaultFails renders ✗ header + 5 lines + (default pass) tag")
    func rendersDefaultFails() {
        let rendered = VerifyResultRenderer.render(
            .defaultFails(
                trial: 47,
                input: "Complex(0.0042, -1.7e6)",
                forwardResult: "Complex(3.1, 2.2)",
                inverseResult: "Complex(99.0, 0.0)"
            ),
            context: Self.canonicalContext
        )
        let lines = rendered.split(separator: "\n")
        #expect(lines.count == 5)
        #expect(lines[0].hasPrefix("✗ verify fails"))
        #expect(rendered.contains("trial 47 (default pass)"))
        #expect(rendered.contains("Complex(0.0042, -1.7e6)"))
        #expect(rendered.contains("isApproximatelyEqual"))
    }

    @Test("error renders ! line with the supplied reason")
    func rendersError() {
        let rendered = VerifyResultRenderer.render(
            .error(reason: "binary crashed: SIGABRT"),
            context: Self.canonicalContext
        )
        #expect(rendered.hasPrefix("! verify error"))
        #expect(rendered.contains("SIGABRT"))
    }

    // MARK: - Round trip

    @Test("end-to-end: both-pass stdout → bothPass outcome → ✓ rendering")
    func endToEndBothPass() {
        let raw = Self.output(
            exitCode: 0,
            stdout: [
                "VERIFY_DEFAULT_RESULT: PASS",
                "VERIFY_DEFAULT_TRIALS: 100",
                "VERIFY_EDGE_RESULT: PASS",
                "VERIFY_EDGE_TRIALS: 100",
                "VERIFY_EDGE_SAMPLED: 12"
            ].joined(separator: "\n")
        )
        let outcome = VerifyResultParser.parse(raw)
        let rendered = VerifyResultRenderer.render(outcome, context: Self.canonicalContext)
        #expect(rendered.hasPrefix("✓ verify holds (strong)"))
    }

    // MARK: - V1.44.D template-aware rendering (idempotence)

    @Test("idempotence + bothPass renders 'idempotence on f over <carrier>'")
    func rendersIdempotenceBothPass() {
        let rendered = VerifyResultRenderer.render(
            .bothPass(defaultTrials: 100, edgeTrials: 100, edgeSampled: 5),
            context: Self.idempotenceContext
        )
        #expect(rendered.contains("idempotence on Complex.normalize over Complex<Double>"))
        // Round-trip phrasing must NOT appear.
        #expect(!rendered.contains("round-trip"))
        #expect(rendered.contains("(5 / 12 curated edge cases sampled)"))
    }

    @Test("idempotence + defaultFails renders f(input) and f(f(input)) lines")
    func rendersIdempotenceDefaultFails() {
        let rendered = VerifyResultRenderer.render(
            .defaultFails(
                trial: 3,
                input: "Complex(1, 2)",
                forwardResult: "Complex(0.5, 1)",
                inverseResult: "Complex(0.25, 0.5)"
            ),
            context: Self.idempotenceContext
        )
        // Forward and inverse expressions reference the same function.
        #expect(rendered.contains("Complex.normalize(input) "))
        #expect(rendered.contains("Complex.normalize(Complex.normalize(input))"))
        // Expected target is f(input), not raw input.
        #expect(rendered.contains("expected ≈ f(input)"))
    }

    @Test("idempotence + edgeCaseAdvisory renders f(input) / f(f(input)) + edge index #0 NaN tag")
    func rendersIdempotenceEdgeCaseAdvisory() {
        let rendered = VerifyResultRenderer.render(
            .edgeCaseAdvisory(
                defaultTrials: 100,
                edgeTrial: 4,
                edgeInput: "Complex(nan, nan)",
                edgeForward: "Complex(nan, nan)",
                edgeInverse: "Complex(nan, nan)",
                edgeCaseIndex: 0
            ),
            context: Self.idempotenceContext
        )
        #expect(rendered.contains("⚠ verify holds for finite domain"))
        #expect(rendered.contains("idempotence on Complex.normalize"))
        #expect(rendered.contains("edge case #0 (Complex(NaN, NaN))"))
        #expect(rendered.contains("Complex.normalize(input) "))
        #expect(rendered.contains("expected ≈ f(input)"))
    }

    // MARK: - V1.44.D integer-carrier sentinel rendering

    @Test("Int + bothPass with edgeTrials=0 renders 'edge pass not applicable'")
    func rendersIntCarrierBothPassSentinel() {
        let rendered = VerifyResultRenderer.render(
            .bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0),
            context: Self.intContext
        )
        #expect(rendered.contains("✓ verify holds (strong)"))
        #expect(rendered.contains("(integer carrier — edge pass not applicable)"))
        // The "curated edge cases sampled" phrasing must NOT appear.
        #expect(!rendered.contains("curated edge cases sampled"))
    }

    // MARK: - V1.44.D Double-carrier single-entry curated rendering

    @Test("Double + bothPass renders 'N / 1 curated edge cases sampled'")
    func rendersDoubleCarrierBothPass() {
        let rendered = VerifyResultRenderer.render(
            .bothPass(defaultTrials: 100, edgeTrials: 100, edgeSampled: 1),
            context: Self.doubleContext
        )
        #expect(rendered.contains("(1 / 1 curated edge cases sampled)"))
    }

    @Test("Double + edgeCaseAdvisory index=0 renders 'edge case #0 (Double.nan)'")
    func rendersDoubleCarrierEdgeCaseAdvisoryNaN() {
        let rendered = VerifyResultRenderer.render(
            .edgeCaseAdvisory(
                defaultTrials: 100,
                edgeTrial: 7,
                edgeInput: "nan",
                edgeForward: "nan",
                edgeInverse: "nan",
                edgeCaseIndex: 0
            ),
            context: Self.doubleContext
        )
        #expect(rendered.contains("edge case #0 (Double.nan)"))
        // The 12-entry Complex labels must NOT leak into Double rendering.
        #expect(!rendered.contains("Complex(NaN"))
    }
}
