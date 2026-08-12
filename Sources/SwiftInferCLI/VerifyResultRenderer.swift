import Foundation

public enum VerifyResultRenderer {

    /// Context the renderer needs to produce a human-readable line.
    /// V1.44.D adds `templateName` so the renderer can adapt the
    /// "round-trip" vs "idempotence" phrasing — `forwardName` /
    /// `inverseName` retain their names but for idempotence the two
    /// fields hold the same single function call (the renderer prints
    /// `f(input)` / `f(f(input))` instead of `forward(input)` /
    /// `reverse(forward(input))`).
    public struct Context: Equatable, Sendable {
        /// `"round-trip"` or `"idempotence"`. Other values render via
        /// the round-trip code path (best-effort fallback).
        public let templateName: String
        public let forwardName: String
        public let inverseName: String
        public let carrierType: String

        public init(
            templateName: String,
            forwardName: String,
            inverseName: String,
            carrierType: String
        ) {
            self.templateName = templateName
            self.forwardName = forwardName
            self.inverseName = inverseName
            self.carrierType = carrierType
        }
    }

    /// Curated-entry labels mirroring `Gen<Complex<Double>>.complexEdgeCases`
    /// order. Used to humanize the edge-case-advisory rendering; index
    /// 0..11 maps 1-to-1 against the kit's array. Adding entries on
    /// the kit side appends here in the same order — existing indices
    /// are stable per the kit's API contract.
    static let edgeCaseLabels: [String] = [
        "Complex(NaN, NaN)",
        "Complex(NaN, 0)",
        "Complex(0, NaN)",
        "Complex(+Infinity, 0)",
        "Complex(-Infinity, 0)",
        "Complex(0, +Infinity)",
        "Complex(0, -Infinity)",
        "Complex(+Infinity, +Infinity)",
        "Complex(0, 0)",
        "Complex(-0.0, 0)",
        "Complex(greatestFiniteMagnitude, 0)",
        "Complex(leastNonzeroMagnitude, 0)"
    ]

    /// Render the outcome as a multi-line user-facing string. V1.44.D
    /// adapts the phrasing per template (`round-trip` vs `idempotence`)
    /// and per carrier (FP edge-pass-sampled count vs the integer
    /// "no edge pass ran" line).
    public static func render(_ outcome: VerifyOutcome, context: Context) -> String {
        switch outcome {
        case let .bothPass(defaultTrials, edgeTrials, edgeSampled):
            return renderBothPass(
                defaultTrials: defaultTrials,
                edgeTrials: edgeTrials,
                edgeSampled: edgeSampled,
                context: context
            )

        case let .edgeCaseAdvisory(defaultTrials, edge):
            return renderEdgeCaseAdvisory(
                defaultTrials: defaultTrials,
                edge: edge,
                context: context
            )

        case let .defaultFails(detail):
            return renderDefaultFails(detail: detail, context: context)

        case let .error(reason):
            return "! verify error: \(reason)"
        }
    }

    // MARK: - Per-outcome renderers

    private static func renderBothPass(
        defaultTrials: Int,
        edgeTrials: Int,
        edgeSampled: Int,
        context: Context
    ) -> String {
        let shape = renderShape(for: context)
        let header = "✓ verify holds (strong): \(shape.subjectLine(context: context)),"
        let trialLine =
            "    \(defaultTrials) default \(trialWord(defaultTrials)) + "
            + "\(edgeTrials) edge-case-biased \(trialWord(edgeTrials)), all pass"
        let coverageLine = edgeCoverageLine(
            edgeTrials: edgeTrials,
            edgeSampled: edgeSampled,
            context: context
        )
        return [header, trialLine, coverageLine].joined(separator: "\n")
    }

    private static func renderEdgeCaseAdvisory(
        defaultTrials: Int,
        edge: EdgeCaseDetail,
        context: Context
    ) -> String {
        let shape = renderShape(for: context)
        let edgeTag = edgeIndexTag(edgeCaseIndex: edge.caseIndex, context: context)
        let heading = [
            "⚠ verify holds for finite domain; edge-case advisory: "
                + "\(shape.subjectLine(context: context)),",
            "    default pass \(defaultTrials)/\(defaultTrials), "
                + "edge pass failed at trial \(edge.trial) on \(edgeTag):"
        ]
        let values = shape.valueLines(
            input: edge.input,
            forward: edge.forward,
            inverse: edge.inverse,
            context: context
        )
        return (heading + values).joined(separator: "\n")
    }

    private static func renderDefaultFails(
        detail: DefaultFailDetail,
        context: Context
    ) -> String {
        let shape = renderShape(for: context)
        var lines = [
            "✗ verify fails: \(shape.subjectLine(context: context)), "
                + "counterexample at trial \(detail.trial) (default pass):"
        ] + shape.valueLines(
            input: detail.input,
            forward: detail.forwardResult,
            inverse: detail.inverseResult,
            context: context
        )
        // v1.141: when the stub shrank the failing input, surface the minimal
        // counterexample — the most actionable form for the developer.
        if let shrink = detail.shrink, shrink.steps > 0 {
            let stepWord = shrink.steps == 1 ? "step" : "steps"
            lines.append(
                "    shrank \(shrink.steps) \(stepWord) → minimal counterexample: "
                    + "\(displayValue(shrink.minimal))"
            )
        }
        return lines.joined(separator: "\n")
    }

    /// V1.151 — render a counterexample value for display. A value with
    /// significant whitespace (leading/trailing space, tab, newline) or an
    /// empty value is shown as an escaped, quoted literal so it's
    /// unambiguous (`"  -"` rather than a bare `-` that reads as no
    /// whitespace). Ordinary values — numbers, plain strings, tuples —
    /// render as-is, so numeric counterexample output is unchanged.
    static func displayValue(_ value: String) -> String {
        let hasEdgeWhitespace = value.first == " " || value.last == " "
        let needsQuoting = value.isEmpty
            || hasEdgeWhitespace
            || value.contains("\n")
            || value.contains("\t")
        guard needsQuoting else { return value }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    // MARK: - Template/carrier-aware phrasing

    /// Phrasing for this verdict, or the round-trip fallback.
    ///
    /// The fallback is a **silent** mis-render, not a safe default: five templates resolved
    /// through it, and a passing `predicate` run printed `round-trip contains/contains` — the
    /// forward name twice, standing in for an inverse the law does not have. Nothing failed; the
    /// verdict was about a different property. It stays because a render must always produce
    /// something, and `VerifiableTemplateReachTests` is what keeps it from hiding anything:
    /// that suite renders every verifiable template and fails on any phrased as a round trip.
    static func renderShape(for context: Context) -> RenderShape {
        RenderShape.byTemplateName[context.templateName] ?? .roundTrip
    }

    /// Edge-coverage line for `.bothPass`. FP carriers map to their curated
    /// list size — 12 entries for `Complex<Double>`, `DoubleEdgeCaseStub`'s
    /// real-axis set for `Double`.
    ///
    /// **`edgeTrials == 0` means the pass did not run, and the line must say
    /// so.** Strategist-routed carriers emit `edgeSentinelSection()` — a
    /// hardcoded `PASS` printing zero trials — so a `bothPass` on such a
    /// carrier is carried entirely by the default pass. The previous wording,
    /// *"(integer carrier — edge pass not applicable)"*, read as *this carrier
    /// has no edge cases*, when the truth is *we did not check them*. `Int.min`
    /// is as much an edge case as `NaN`; `fixtures/verify-refutability` has a
    /// stub wrong only there that this pass reported as holding.
    ///
    /// Since V1.153 the integer and `String` boundary values are mixed into the
    /// *default* generator, so they are reachable in the pass that did run —
    /// but that is generator bias, not a second pass, and the line should not
    /// claim coverage it cannot count.
    private static func edgeCoverageLine(
        edgeTrials: Int,
        edgeSampled: Int,
        context: Context
    ) -> String {
        if edgeTrials == 0 {
            return "    (no edge pass ran for this carrier — "
                + "boundary values are mixed into the default generator instead)"
        }
        let curatedCount = curatedEdgeCaseCount(for: context.carrierType)

        // **A carrier with no curated table used to render `0 / 0`.** Only
        // `Complex<Double>` and `Double` have an indexed edge-case list, so every
        // other carrier that DID run an edge pass printed a zero numerator over a
        // zero denominator — which reads as *the edge pass covered nothing*, when
        // the truth is that `edgeTrials` boundary-biased trials ran and there is
        // no table to count them against. Two verifies on a `String` carrier
        // reported `100 edge-case-biased trials, all pass` and then
        // `(0 / 0 curated edge cases sampled)` on the next line, which is the
        // confident-zero shape this project keeps designing against — found by
        // pointing the tool at SwiftProjectLint on 2026-08-11.
        //
        // The population is not marginal and it grew with a fix: extending the
        // edge pass to composed carriers (2026-08-07) moved 35 verdicts off the
        // zero-trial sentinel, and every one of them lands here.
        guard curatedCount > 0 else {
            return "    (\(edgeTrials) boundary-biased \(trialWord(edgeTrials)) ran; "
                + "no curated edge-case table exists for \(context.carrierType), "
                + "so there is no index to report coverage against)"
        }
        return "    (\(edgeSampled) / \(curatedCount) curated edge cases sampled)"
    }

    /// Per-carrier curated edge-case index tag for `.edgeCaseAdvisory`.
    /// `Complex<Double>` uses the 12-entry `edgeCaseLabels` table;
    /// `Double` uses `DoubleEdgeCaseStub`'s real-axis labels.
    private static func edgeIndexTag(
        edgeCaseIndex: Int,
        context: Context
    ) -> String {
        guard edgeCaseIndex >= 0 else {
            return "a non-curated value"
        }
        switch context.carrierType {
        case "Complex<Double>":
            guard edgeCaseIndex < edgeCaseLabels.count else {
                return "a non-curated value"
            }
            return "edge case #\(edgeCaseIndex) (\(edgeCaseLabels[edgeCaseIndex]))"

        case "Double":
            // Curated real-axis set — see `DoubleEdgeCaseStub`.
            guard edgeCaseIndex < DoubleEdgeCaseStub.labels.count else {
                return "a non-curated value"
            }
            return "edge case #\(edgeCaseIndex) (\(DoubleEdgeCaseStub.labels[edgeCaseIndex]))"

        default:
            // Int carrier shouldn't fire `.edgeCaseAdvisory` (no edge
            // pass) — defensive fallback.
            return "a non-curated value"
        }
    }

    private static func curatedEdgeCaseCount(for carrierType: String) -> Int {
        switch carrierType {
        case "Complex<Double>": return edgeCaseLabels.count
        case "Double": return DoubleEdgeCaseStub.curatedCount
        default: return 0
        }
    }

    private static func trialWord(_ count: Int) -> String {
        count == 1 ? "trial" : "trials"
    }
}
