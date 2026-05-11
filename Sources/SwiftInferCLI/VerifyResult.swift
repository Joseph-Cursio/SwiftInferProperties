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

        let snippet = lines.suffix(5).joined(separator: " | ")
        let reason = "verifier subprocess exited with code \(output.exitCode), "
            + "stdout (last 5 lines, pipe-joined): \(snippet)"
        return .error(reason: reason)
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
}

public enum VerifyResultRenderer {

    /// Context the renderer needs to produce a human-readable line.
    public struct Context: Equatable, Sendable {
        public let forwardName: String
        public let inverseName: String
        public let carrierType: String

        public init(forwardName: String, inverseName: String, carrierType: String) {
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

    /// Render the outcome as a multi-line user-facing string. Both
    /// strong-pass and edge-advisory cases span multiple lines; the
    /// fail and error cases match v1.42's shape.
    public static func render(_ outcome: VerifyOutcome, context: Context) -> String {
        switch outcome {
        case let .bothPass(defaultTrials, edgeTrials, edgeSampled):
            return [
                "✓ verify holds (strong): round-trip \(context.forwardName)/\(context.inverseName) "
                    + "over \(context.carrierType),",
                "    \(defaultTrials) default \(trialWord(defaultTrials)) + "
                    + "\(edgeTrials) edge-case-biased \(trialWord(edgeTrials)), all pass",
                "    (\(edgeSampled) / \(edgeCaseLabels.count) curated edge cases sampled)"
            ].joined(separator: "\n")

        case let .edgeCaseAdvisory(
            defaultTrials,
            edgeTrial,
            edgeInput,
            edgeForward,
            edgeInverse,
            edgeCaseIndex
        ):
            let edgeTag: String
            if edgeCaseIndex >= 0, edgeCaseIndex < edgeCaseLabels.count {
                edgeTag = "edge case #\(edgeCaseIndex) (\(edgeCaseLabels[edgeCaseIndex]))"
            } else {
                edgeTag = "a non-curated value"
            }
            return [
                "⚠ verify holds for finite domain; edge-case advisory: "
                    + "round-trip \(context.forwardName)/\(context.inverseName) "
                    + "over \(context.carrierType),",
                "    default pass \(defaultTrials)/\(defaultTrials), "
                    + "edge pass failed at trial \(edgeTrial) on \(edgeTag):",
                "    input  = \(edgeInput)",
                "    \(context.forwardName)(input)  = \(edgeForward)",
                "    \(context.inverseName)(\(context.forwardName)(input)) = \(edgeInverse)",
                "    expected ≈ input (within \(context.carrierType).isApproximatelyEqual)"
            ].joined(separator: "\n")

        case let .defaultFails(trial, input, forwardResult, inverseResult):
            return [
                "✗ verify fails: round-trip \(context.forwardName)/\(context.inverseName) "
                    + "over \(context.carrierType), counterexample at trial \(trial) (default pass):",
                "    input  = \(input)",
                "    \(context.forwardName)(input)  = \(forwardResult)",
                "    \(context.inverseName)(\(context.forwardName)(input)) = \(inverseResult)",
                "    expected ≈ input (within \(context.carrierType).isApproximatelyEqual)"
            ].joined(separator: "\n")

        case let .error(reason):
            return "! verify error: \(reason)"
        }
    }

    private static func trialWord(_ count: Int) -> String {
        count == 1 ? "trial" : "trials"
    }
}
