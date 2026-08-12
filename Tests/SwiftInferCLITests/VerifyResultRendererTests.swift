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

    /// A carrier that DOES run an edge pass and has no curated edge-case table — the population
    /// the `0 / 0` line was rendering for. `String` is the one the defect was measured on.
    private static let stringContext = VerifyResultRenderer.Context(
        templateName: "idempotence",
        forwardName: "NameListReader.normalize",
        inverseName: "NameListReader.normalize",
        carrierType: "String"
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
                edge: EdgeCaseDetail(
                    trial: 7,
                    input: "Complex(nan, 0.0)",
                    forward: "Complex(nan, nan)",
                    inverse: "Complex(nan, nan)",
                    caseIndex: 1
                )
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
                edge: EdgeCaseDetail(
                    trial: 3,
                    input: "Complex(1.5, -2.5)",
                    forward: "Complex(3.0, -5.0)",
                    inverse: "Complex(0.0, 0.0)",
                    caseIndex: -1
                )
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
                inverseResult: "Complex(99.0, 0.0)",
                shrunk: nil,
                shrinkSteps: 0
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

    @Test("defaultFails with a shrunk input renders the minimal counterexample line (v1.141)")
    func rendersDefaultFailsWithShrink() {
        let rendered = VerifyResultRenderer.render(
            .defaultFails(
                trial: 47,
                input: "Complex(0.0042, -1.7e6)",
                forwardResult: "Complex(3.1, 2.2)",
                inverseResult: "Complex(99.0, 0.0)",
                shrunk: "Complex(0.0, 0.0)",
                shrinkSteps: 14
            ),
            context: Self.canonicalContext
        )
        let lines = rendered.split(separator: "\n")
        #expect(lines.count == 6) // the 5 base lines + the shrink line
        #expect(rendered.contains("shrank 14 steps → minimal counterexample: Complex(0.0, 0.0)"))
        // The original first-failing input is still shown above it.
        #expect(rendered.contains("Complex(0.0042, -1.7e6)"))
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
                inverseResult: "Complex(0.25, 0.5)",
                shrunk: nil,
                shrinkSteps: 0
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
                edge: EdgeCaseDetail(
                    trial: 4,
                    input: "Complex(nan, nan)",
                    forward: "Complex(nan, nan)",
                    inverse: "Complex(nan, nan)",
                    caseIndex: 0
                )
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

    /// V1.153 — the wording changed because it was misleading. `edgeTrials == 0`
    /// means the pass did NOT run; the old text ("edge pass not applicable")
    /// read as "this carrier has no edge cases", which is false — `Int.min` is
    /// as much an edge case as `NaN`.
    @Test("Int + bothPass with edgeTrials=0 says the edge pass did not run")
    func rendersIntCarrierBothPassSentinel() {
        let rendered = VerifyResultRenderer.render(
            .bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0),
            context: Self.intContext
        )
        #expect(rendered.contains("✓ verify holds (strong)"))
        #expect(rendered.contains("no edge pass ran for this carrier"))
        // The "curated edge cases sampled" phrasing must NOT appear.
        #expect(!rendered.contains("curated edge cases sampled"))
    }

    // MARK: - A carrier that runs an edge pass but has no curated table

    /// A carrier with no indexed edge-case list must not report `0 / 0`.
    ///
    /// Only `Complex<Double>` and `Double` have a curated table, so every other carrier that runs
    /// an edge pass used to render a zero numerator over a zero denominator — which reads as *the
    /// edge pass covered nothing*, while `edgeTrials` boundary-biased trials had in fact run.
    /// Measured on SwiftProjectLint, 2026-08-11: two `String`-carrier verifies printed
    /// `100 edge-case-biased trials, all pass` and then `(0 / 0 curated edge cases sampled)`.
    ///
    /// **Both halves are asserted, and the negative one is the point.** Checking only that the new
    /// sentence appears would still pass if `0 / 0` were printed beside it; the population is every
    /// composed carrier the 2026-08-07 edge-pass extension reached, so the wrong line reappearing
    /// is the failure worth catching.
    @Test("a carrier with no curated table reports trials ran, not 0 / 0")
    func rendersUncuratedCarrierEdgeCoverageWithoutAZeroFraction() {
        let rendered = VerifyResultRenderer.render(
            .bothPass(defaultTrials: 100, edgeTrials: 100, edgeSampled: 0),
            context: Self.stringContext
        )

        #expect(rendered.contains("100 boundary-biased trials ran"))
        #expect(rendered.contains("no curated edge-case table exists for String"))
        #expect(!rendered.contains("0 / 0"))
        #expect(!rendered.contains("curated edge cases sampled"))
    }
}

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
