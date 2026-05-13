import Foundation

/// V1.43.C — parses the two-pass verifier subprocess output into a
/// structured `VerifyOutcome` and renders it for human consumption.
///
/// **Four v1.43 outcomes** (extends v1.42's 3-way pass/fail/error):
///
///   - `.bothPass(defaultTrials:edgeTrials:edgeSampled:)` — strong
///     evidence; default + edge passes both clean.
///   - `.edgeCaseAdvisory(defaultTrials:edgeTrial:edgeInput:edgeForward:`
///     `edgeInverse:edgeCaseIndex:)` — default pass clean, edge pass
///     surfaced a counterexample at a curated edge case (or, less
///     commonly, a finite-path value on the 90% slice — `edgeCaseIndex
///     == -1`). Property holds for normal inputs but breaks at a
///     boundary.
///   - `.defaultFails(trial:input:forwardResult:inverseResult:)` —
///     default pass surfaced a counterexample; edge pass was skipped
///     by the runner per the proposal §2.2 row 3 short-circuit.
///   - `.error(reason:)` — build failure, runner crash, missing
///     markers, or unexpected exit code.
///
/// **Parsing convention.** The V1.43.B stub emits one
/// `VERIFY_DEFAULT_<KEY>:` or `VERIFY_EDGE_<KEY>:` line per data point.
/// The parser is tolerant of extra lines (build chatter, debug prints,
/// etc.) — it locates each marker by line prefix and ignores anything
/// else. Multiple matches of the same marker take the *first* hit.
public enum VerifyOutcome: Equatable, Sendable {
    case bothPass(defaultTrials: Int, edgeTrials: Int, edgeSampled: Int)
    case edgeCaseAdvisory(
        defaultTrials: Int,
        edgeTrial: Int,
        edgeInput: String,
        edgeForward: String,
        edgeInverse: String,
        edgeCaseIndex: Int
    )
    case defaultFails(
        trial: Int,
        input: String,
        forwardResult: String,
        inverseResult: String
    )
    case error(reason: String)
}

public enum VerifyResultParser {

    /// Parse a `VerifierSubprocess.Output` into a `VerifyOutcome`.
    ///
    /// Decision order (mutually exclusive by stub-side short-circuit):
    ///   1. `VERIFY_DEFAULT_RESULT: FAIL` + exit 1 → `.defaultFails`.
    ///   2. `VERIFY_DEFAULT_RESULT: PASS` + `VERIFY_EDGE_RESULT: FAIL`
    ///      + exit 1 → `.edgeCaseAdvisory`.
    ///   3. `VERIFY_DEFAULT_RESULT: PASS` + `VERIFY_EDGE_RESULT: PASS`
    ///      + exit 0 → `.bothPass`.
    ///   4. Otherwise → `.error` with a load-bearing reason including
    ///      the exit code and a short stdout snippet.
    public static func parse(_ output: VerifierSubprocess.Output) -> VerifyOutcome {
        let lines = output.stdout.split(separator: "\n").map(String.init)
        let defaultPass = lines.first(where: { $0.hasPrefix("VERIFY_DEFAULT_RESULT: PASS") }) != nil
        let defaultFail = lines.first(where: { $0.hasPrefix("VERIFY_DEFAULT_RESULT: FAIL") }) != nil
        let edgePass = lines.first(where: { $0.hasPrefix("VERIFY_EDGE_RESULT: PASS") }) != nil
        let edgeFail = lines.first(where: { $0.hasPrefix("VERIFY_EDGE_RESULT: FAIL") }) != nil

        if defaultFail, output.exitCode == 1 {
            let trial = Int(value(forMarker: "VERIFY_DEFAULT_TRIAL:", in: lines) ?? "") ?? -1
            let input = value(forMarker: "VERIFY_DEFAULT_INPUT:", in: lines) ?? "(missing)"
            let forwardResult = value(forMarker: "VERIFY_DEFAULT_FORWARD:", in: lines) ?? "(missing)"
            let inverseResult = value(forMarker: "VERIFY_DEFAULT_INVERSE:", in: lines) ?? "(missing)"
            return .defaultFails(
                trial: trial,
                input: input,
                forwardResult: forwardResult,
                inverseResult: inverseResult
            )
        }

        if defaultPass, edgeFail, output.exitCode == 1 {
            let defaultTrials = Int(value(forMarker: "VERIFY_DEFAULT_TRIALS:", in: lines) ?? "") ?? 0
            let edgeTrial = Int(value(forMarker: "VERIFY_EDGE_TRIAL:", in: lines) ?? "") ?? -1
            let edgeInput = value(forMarker: "VERIFY_EDGE_INPUT:", in: lines) ?? "(missing)"
            let edgeForward = value(forMarker: "VERIFY_EDGE_FORWARD:", in: lines) ?? "(missing)"
            let edgeInverse = value(forMarker: "VERIFY_EDGE_INVERSE:", in: lines) ?? "(missing)"
            let edgeCaseIndex = Int(value(forMarker: "VERIFY_EDGE_INDEX:", in: lines) ?? "") ?? -1
            return .edgeCaseAdvisory(
                defaultTrials: defaultTrials,
                edgeTrial: edgeTrial,
                edgeInput: edgeInput,
                edgeForward: edgeForward,
                edgeInverse: edgeInverse,
                edgeCaseIndex: edgeCaseIndex
            )
        }

        if defaultPass, edgePass, output.exitCode == 0 {
            let defaultTrials = Int(value(forMarker: "VERIFY_DEFAULT_TRIALS:", in: lines) ?? "") ?? 0
            let edgeTrials = Int(value(forMarker: "VERIFY_EDGE_TRIALS:", in: lines) ?? "") ?? 0
            let edgeSampled = Int(value(forMarker: "VERIFY_EDGE_SAMPLED:", in: lines) ?? "") ?? 0
            return .bothPass(
                defaultTrials: defaultTrials,
                edgeTrials: edgeTrials,
                edgeSampled: edgeSampled
            )
        }

        return .error(reason: parseErrorReason(from: output))
    }

    /// V1.52.B — build the `.error` detail string from the raw
    /// subprocess output. Cycle-48 measurement (`docs/
    /// calibration-cycle-48-findings.md`) hit 11 subprocess SIGABRTs
    /// (exit 6) with empty stdout — the trap reason printed by the
    /// Swift runtime lands on stderr, so the parse-error path now
    /// surfaces both streams. Stderr is appended only when non-empty
    /// so pre-cycle-48 cases (build-failure stderr already captured
    /// upstream as a different error path) don't gain noise.
    private static func parseErrorReason(
        from output: VerifierSubprocess.Output
    ) -> String {
        let stdoutSnippet = pipeJoinedTail(of: output.stdout)
        var reason = "verifier subprocess exited with code \(output.exitCode), "
            + "stdout (last 5 lines, pipe-joined): \(stdoutSnippet)"
        let stderrSnippet = pipeJoinedTail(of: output.stderr)
        if !stderrSnippet.isEmpty {
            reason += "; stderr (last 5 lines, pipe-joined): \(stderrSnippet)"
        }
        return reason
    }

    /// Extract the value following a `MARKER:` prefix on the first
    /// matching line.
    private static func value(forMarker marker: String, in lines: [String]) -> String? {
        for line in lines where line.hasPrefix(marker) {
            let value = String(line.dropFirst(marker.count))
            return value.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// V1.52.B — return the last 5 lines of `stream`, pipe-joined,
    /// with each line truncated to 200 characters (ellipsis suffix on
    /// truncation). Empty input → empty output. Used for both stdout
    /// and stderr in the parse-error detail string.
    ///
    /// **Why per-line truncation.** A single multi-line build error
    /// can produce a 5-line tail where one line is several KB
    /// (template-instantiation stack traces). Capping per line keeps
    /// the JSON survey record tractable — the cycle-48 survey doc
    /// is already 10KB+ for 109 rows; an uncapped stderr field
    /// could push individual rows past 100KB.
    private static func pipeJoinedTail(of stream: String) -> String {
        let trimmed = stream.split(separator: "\n").map(String.init)
        let lastFive = trimmed.suffix(5).map { line -> String in
            if line.count > 200 {
                let prefix = line.prefix(200)
                return "\(prefix)…"
            }
            return line
        }
        return lastFive.joined(separator: " | ")
    }
}

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

        case let .edgeCaseAdvisory(
            defaultTrials,
            edgeTrial,
            edgeInput,
            edgeForward,
            edgeInverse,
            edgeCaseIndex
        ):
            let payload = EdgeAdvisoryPayload(
                defaultTrials: defaultTrials,
                edgeTrial: edgeTrial,
                edgeInput: edgeInput,
                edgeForward: edgeForward,
                edgeInverse: edgeInverse,
                edgeCaseIndex: edgeCaseIndex
            )
            return renderEdgeCaseAdvisory(payload: payload, context: context)

        case let .defaultFails(trial, input, forwardResult, inverseResult):
            return renderDefaultFails(
                trial: trial,
                input: input,
                forwardResult: forwardResult,
                inverseResult: inverseResult,
                context: context
            )

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

    fileprivate struct EdgeAdvisoryPayload {
        let defaultTrials: Int
        let edgeTrial: Int
        let edgeInput: String
        let edgeForward: String
        let edgeInverse: String
        let edgeCaseIndex: Int
    }

    private static func renderEdgeCaseAdvisory(
        payload: EdgeAdvisoryPayload,
        context: Context
    ) -> String {
        let shape = renderShape(for: context)
        let edgeTag = edgeIndexTag(edgeCaseIndex: payload.edgeCaseIndex, context: context)
        return [
            "⚠ verify holds for finite domain; edge-case advisory: "
                + "\(shape.subjectLine(context: context)),",
            "    default pass \(payload.defaultTrials)/\(payload.defaultTrials), "
                + "edge pass failed at trial \(payload.edgeTrial) on \(edgeTag):",
            "    input  = \(payload.edgeInput)",
            "    \(shape.forwardExpression(context: context)) = \(payload.edgeForward)",
            "    \(shape.inverseExpression(context: context)) = \(payload.edgeInverse)",
            "    expected ≈ \(shape.expectedExpression(context: context)) "
                + "(within \(context.carrierType).isApproximatelyEqual)"
        ].joined(separator: "\n")
    }

    private static func renderDefaultFails(
        trial: Int,
        input: String,
        forwardResult: String,
        inverseResult: String,
        context: Context
    ) -> String {
        let shape = renderShape(for: context)
        return [
            "✗ verify fails: \(shape.subjectLine(context: context)), "
                + "counterexample at trial \(trial) (default pass):",
            "    input  = \(input)",
            "    \(shape.forwardExpression(context: context)) = \(forwardResult)",
            "    \(shape.inverseExpression(context: context)) = \(inverseResult)",
            "    expected ≈ \(shape.expectedExpression(context: context)) "
                + "(within \(context.carrierType).isApproximatelyEqual)"
        ].joined(separator: "\n")
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
    /// list size — 12 entries for `Complex<Double>`, 1 entry
    /// (`Double.nan`) for `Double`.
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
    /// `Double` uses a single-entry `[Double.nan]` synthesized label.
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
            // Single-entry curated list — index 0 is NaN per V1.44.B.
            return edgeCaseIndex == 0
                ? "edge case #0 (Double.nan)"
                : "a non-curated value"
        default:
            // Int carrier shouldn't fire `.edgeCaseAdvisory` (no edge
            // pass) — defensive fallback.
            return "a non-curated value"
        }
    }

    private static func curatedEdgeCaseCount(for carrierType: String) -> Int {
        switch carrierType {
        case "Complex<Double>": return edgeCaseLabels.count
        case "Double": return 1
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
