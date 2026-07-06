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
    /// "edge pass not applicable" sentinel).
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
        return [
            "⚠ verify holds for finite domain; edge-case advisory: "
                + "\(shape.subjectLine(context: context)),",
            "    default pass \(defaultTrials)/\(defaultTrials), "
                + "edge pass failed at trial \(edge.trial) on \(edgeTag):",
            "    input  = \(displayValue(edge.input))",
            "    \(shape.forwardExpression(context: context)) = \(displayValue(edge.forward))",
            "    \(shape.inverseExpression(context: context)) = \(displayValue(edge.inverse))",
            "    expected ≈ \(shape.expectedExpression(context: context)) "
                + "(within \(context.carrierType).isApproximatelyEqual)"
        ].joined(separator: "\n")
    }

    private static func renderDefaultFails(
        detail: DefaultFailDetail,
        context: Context
    ) -> String {
        let shape = renderShape(for: context)
        var lines = [
            "✗ verify fails: \(shape.subjectLine(context: context)), "
                + "counterexample at trial \(detail.trial) (default pass):",
            "    input  = \(displayValue(detail.input))",
            "    \(shape.forwardExpression(context: context)) = \(displayValue(detail.forwardResult))",
            "    \(shape.inverseExpression(context: context)) = \(displayValue(detail.inverseResult))",
            "    expected ≈ \(shape.expectedExpression(context: context)) "
                + "(within \(context.carrierType).isApproximatelyEqual)"
        ]
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

    fileprivate static func renderShape(for context: Context) -> RenderShape {
        switch context.templateName {
        case "idempotence": return RenderShape(kind: .idempotence)
        case "commutativity": return RenderShape(kind: .commutativity)
        case "associativity": return RenderShape(kind: .associativity)
        case "idempotence-lifted": return RenderShape(kind: .idempotenceLifted)
        case "dual-style-consistency": return RenderShape(kind: .dualStyleConsistency)
        case "monotonicity": return RenderShape(kind: .monotonicity)
        default: return RenderShape(kind: .roundTrip)
        }
    }

    /// Edge-coverage line for `.bothPass`. The integer carrier emits a
    /// zero-edge sentinel (`edgeTrials == 0` per V1.44.B/C); the
    /// renderer detects it and reports the n/a phrasing instead of the
    /// curated-cases-sampled count. FP carriers map to their curated
    /// list size — 12 entries for `Complex<Double>`, `DoubleEdgeCaseStub`'s
    /// real-axis set for `Double`.
    private static func edgeCoverageLine(
        edgeTrials: Int,
        edgeSampled: Int,
        context: Context
    ) -> String {
        if edgeTrials == 0 {
            return "    (integer carrier — edge pass not applicable)"
        }
        let curatedCount = curatedEdgeCaseCount(for: context.carrierType)
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

/// Per-template render-time phrasing helper. File-scoped to keep
/// the type-hierarchy within SwiftLint's `nesting` rule.
private struct RenderShape {
    enum Kind {
        case roundTrip, idempotence, commutativity, associativity
        case idempotenceLifted, dualStyleConsistency, monotonicity
    }

    let kind: Kind

    func subjectLine(context: VerifyResultRenderer.Context) -> String {
        switch kind {
        case .roundTrip:
            return "round-trip \(context.forwardName)/\(context.inverseName) "
                + "over \(context.carrierType)"

        case .idempotence:
            return "idempotence on \(context.forwardName) over \(context.carrierType)"

        case .commutativity:
            return "commutativity on \(context.forwardName) over \(context.carrierType)"

        case .associativity:
            return "associativity on \(context.forwardName) over \(context.carrierType)"

        case .idempotenceLifted:
            return "idempotence-lifted on \(context.forwardName) over [\(context.carrierType)]"

        case .dualStyleConsistency:
            return "dual-style-consistency on \(context.forwardName)/\(context.inverseName) "
                + "over \(context.carrierType)"

        case .monotonicity:
            return "monotonicity on \(context.forwardName) over \(context.carrierType)"
        }
    }

    /// First value line. RT/idempotence: `f(input)`; commutativity:
    /// `f(lhs, rhs)`; associativity: `f(f(a, b), c)`;
    /// idempotence-lifted: `f(xs)`; dual-style-consistency:
    /// `nonMut(x)`; monotonicity: `f(a)` (where a ≤ b).
    func forwardExpression(context: VerifyResultRenderer.Context) -> String {
        switch kind {
        case .roundTrip, .idempotence: return "\(context.forwardName)(input) "
        case .commutativity: return "\(context.forwardName)(lhs, rhs) "

        case .associativity:
            return "\(context.forwardName)(\(context.forwardName)(a, b), c) "

        case .idempotenceLifted:
            return "\(context.forwardName)(xs) "

        case .dualStyleConsistency:
            return "\(context.forwardName)(x) "

        case .monotonicity:
            return "\(context.forwardName)(a) "
        }
    }

    /// Second value line. RT: `reverse(forward(input))`; idempotence:
    /// `f(f(input))`; commutativity: `f(rhs, lhs)`; associativity:
    /// `f(a, f(b, c))`; idempotence-lifted: `f(f(xs))`;
    /// dual-style-consistency: `{ var c = x; c.mut(); c }`;
    /// monotonicity: `f(b)` (where a ≤ b).
    func inverseExpression(context: VerifyResultRenderer.Context) -> String {
        switch kind {
        case .roundTrip: return "\(context.inverseName)(\(context.forwardName)(input))"
        case .idempotence: return "\(context.forwardName)(\(context.forwardName)(input))"
        case .commutativity: return "\(context.forwardName)(rhs, lhs)"

        case .associativity:
            return "\(context.forwardName)(a, \(context.forwardName)(b, c))"

        case .idempotenceLifted:
            return "\(context.forwardName)(\(context.forwardName)(xs))"

        case .dualStyleConsistency:
            return "{ var copy = x; copy.\(context.inverseName)(); return copy }()"

        case .monotonicity:
            return "\(context.forwardName)(b)"
        }
    }

    /// Per-template expected expression. RT: `input`; idempotence:
    /// `f(input)`; commutativity: `f(rhs, lhs)`; associativity:
    /// `f(a, f(b, c))`; idempotence-lifted: `f(xs)`;
    /// dual-style-consistency: `nonMut(x)`; monotonicity:
    /// `f(a) ≤ f(b) when a ≤ b`.
    func expectedExpression(context: VerifyResultRenderer.Context) -> String {
        switch kind {
        case .roundTrip: return "input"
        case .idempotence: return "f(input)"
        case .commutativity: return "\(context.forwardName)(rhs, lhs)"

        case .associativity:
            return "\(context.forwardName)(a, \(context.forwardName)(b, c))"

        case .idempotenceLifted:
            return "\(context.forwardName)(xs)"

        case .dualStyleConsistency:
            return "\(context.forwardName)(x)"

        case .monotonicity:
            return "f(a) ≤ f(b) when a ≤ b"
        }
    }
}
