import Foundation

/// V1.42.C.4 — parses the verifier subprocess output into a structured
/// `VerifyOutcome` and renders it for human consumption.
///
/// **Three v1.42 outcomes** (the four-outcome two-pass table lands in
/// v1.43 when the edge-case-biased generator pass joins):
///
///   - `.pass(trials:)` — all trials passed.
///   - `.fail(trial:input:forwardResult:inverseResult:)` — a trial's
///     `inverse(forward(value))` didn't round-trip to `value` (within
///     `isApproximatelyEqual`).
///   - `.error(reason:)` — build failure, runner crash, missing
///     markers in stdout, or unexpected exit code. The reason string
///     is load-bearing; v1.42 callers print it on stderr.
///
/// **Parsing convention.** The C.2 stub emits one `VERIFY_<KEY>: <value>`
/// line per data point. The parser is tolerant of extra lines (build
/// chatter, debug prints, etc.) — it locates each marker by line
/// prefix and ignores anything else. Multiple matches of the same
/// marker take the *first* hit (the stub never emits a second pass /
/// fail block in v1.42 since `exit(1)` runs after the first failing
/// trial).
public enum VerifyOutcome: Equatable, Sendable {
    case pass(trials: Int)
    case fail(trial: Int, input: String, forwardResult: String, inverseResult: String)
    case error(reason: String)
}

public enum VerifyResultParser {

    /// Parse a `VerifierSubprocess.Output` into a `VerifyOutcome`.
    ///
    /// Decision order:
    ///   1. If stdout contains `"VERIFY_RESULT: PASS"` AND exit code
    ///      is 0 → `.pass(trials:)` using the `VERIFY_TRIALS:` value.
    ///   2. If stdout contains `"VERIFY_RESULT: FAIL"` AND exit code
    ///      is 1 → `.fail(...)` populated from the per-marker values.
    ///   3. Otherwise → `.error(reason:)` with a load-bearing message
    ///      including the exit code and a short stdout snippet.
    public static func parse(_ output: VerifierSubprocess.Output) -> VerifyOutcome {
        let lines = output.stdout.split(separator: "\n").map(String.init)
        let pass = lines.first(where: { $0.hasPrefix("VERIFY_RESULT: PASS") }) != nil
        let fail = lines.first(where: { $0.hasPrefix("VERIFY_RESULT: FAIL") }) != nil

        if pass, output.exitCode == 0 {
            let trials = Int(value(forMarker: "VERIFY_TRIALS:", in: lines) ?? "") ?? 0
            return .pass(trials: trials)
        }
        if fail, output.exitCode == 1 {
            let trial = Int(value(forMarker: "VERIFY_TRIAL:", in: lines) ?? "") ?? -1
            let input = value(forMarker: "VERIFY_INPUT:", in: lines) ?? "(missing)"
            let forwardResult = value(forMarker: "VERIFY_FORWARD:", in: lines) ?? "(missing)"
            let inverseResult = value(forMarker: "VERIFY_INVERSE:", in: lines) ?? "(missing)"
            return .fail(
                trial: trial,
                input: input,
                forwardResult: forwardResult,
                inverseResult: inverseResult
            )
        }

        // Otherwise: missing markers, exit code mismatch, or both.
        let snippet = lines.suffix(5).joined(separator: " | ")
        let reason = "verifier subprocess exited with code \(output.exitCode), "
            + "stdout (last 5 lines, pipe-joined): \(snippet)"
        return .error(reason: reason)
    }

    /// Extract the value following a `MARKER:` prefix on the first
    /// matching line. The marker is matched against the line's full
    /// prefix to avoid false positives from the stub's own log lines.
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
    /// V1.42 supplies `forwardName` / `inverseName` from the
    /// caller's pair-resolution (currently the curated round-trip
    /// pair list; future C.6 may resolve from Evidence directly),
    /// and `carrierType` from the `SemanticIndexEntry.typeName`.
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

    /// Render the outcome as a multi-line user-facing string. Pass +
    /// error are single-line; fail spans 5 lines (header + 4
    /// counterexample rows).
    public static func render(_ outcome: VerifyOutcome, context: Context) -> String {
        switch outcome {
        case let .pass(trials):
            return "✓ verify holds: round-trip \(context.forwardName)/\(context.inverseName) "
                + "over \(context.carrierType), \(trials) trial\(trials == 1 ? "" : "s"), all pass"

        case let .fail(trial, input, forwardResult, inverseResult):
            return [
                "✗ verify fails: round-trip \(context.forwardName)/\(context.inverseName) "
                    + "over \(context.carrierType), counterexample at trial \(trial):",
                "    input  = \(input)",
                "    \(context.forwardName)(input)  = \(forwardResult)",
                "    \(context.inverseName)(\(context.forwardName)(input)) = \(inverseResult)",
                "    expected ≈ input (within \(context.carrierType).isApproximatelyEqual)"
            ].joined(separator: "\n")

        case let .error(reason):
            return "! verify error: \(reason)"
        }
    }
}
