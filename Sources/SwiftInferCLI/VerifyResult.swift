import Foundation

/// The edge-pass counterexample data carried by
/// `VerifyOutcome.edgeCaseAdvisory`.
///
/// Grouped into a struct so the enum case stays within a readable
/// associated-value count. `defaultTrials` stays on the case itself —
/// it describes the *default* pass, not this edge counterexample.
public struct EdgeCaseDetail: Equatable, Sendable {
    /// The edge-pass trial index at which the counterexample surfaced.
    public let trial: Int
    /// The failing edge input, as rendered by the verifier stub.
    public let input: String
    /// The forward-call result on `input`.
    public let forward: String
    /// The inverse-call result on `input`.
    public let inverse: String
    /// The curated edge-case index — `-1` for a non-curated
    /// finite-slice value.
    public let caseIndex: Int

    public init(
        trial: Int,
        input: String,
        forward: String,
        inverse: String,
        caseIndex: Int
    ) {
        self.trial = trial
        self.input = input
        self.forward = forward
        self.inverse = inverse
        self.caseIndex = caseIndex
    }
}

/// V1.43.C — parses the two-pass verifier subprocess output into a
/// structured `VerifyOutcome` and renders it for human consumption.
///
/// **Four v1.43 outcomes** (extends v1.42's 3-way pass/fail/error):
///
///   - `.bothPass(defaultTrials:edgeTrials:edgeSampled:)` — strong
///     evidence; default + edge passes both clean.
///   - `.edgeCaseAdvisory(defaultTrials:edge:)` — default pass clean,
///     edge pass surfaced a counterexample at a curated edge case (or,
///     less commonly, a finite-path value on the 90% slice —
///     `edge.caseIndex == -1`). Property holds for normal inputs but
///     breaks at a boundary.
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
/// v1.141 — the minimal counterexample a verify stub shrank the failing input
/// down to, plus how many steps it took. Bundled (like `EdgeCaseDetail`) so
/// `DefaultFailDetail` stays within the associated-value / parameter lints.
public struct ShrinkTrace: Equatable, Sendable {
    /// The minimal still-failing input, as rendered by the stub.
    public let minimal: String
    /// The number of shrink steps taken to reach `minimal`.
    public let steps: Int

    public init(minimal: String, steps: Int) {
        self.minimal = minimal
        self.steps = steps
    }
}

/// The default-pass counterexample carried by `VerifyOutcome.defaultFails`.
/// Bundled into a struct (mirroring `EdgeCaseDetail`) so the enum case stays
/// within a readable associated-value count.
public struct DefaultFailDetail: Equatable, Sendable {
    /// The default-pass trial index at which the counterexample surfaced.
    public let trial: Int
    /// The first failing input, as rendered by the stub.
    public let input: String
    /// The forward-call result on `input`.
    public let forwardResult: String
    /// The inverse-call result on `input`.
    public let inverseResult: String
    /// The shrink result (v1.141), or `nil` when the stub ran no shrink phase.
    public let shrink: ShrinkTrace?

    public init(
        trial: Int,
        input: String,
        forwardResult: String,
        inverseResult: String,
        shrink: ShrinkTrace? = nil
    ) {
        self.trial = trial
        self.input = input
        self.forwardResult = forwardResult
        self.inverseResult = inverseResult
        self.shrink = shrink
    }
}

public enum VerifyOutcome: Equatable, Sendable {
    case bothPass(defaultTrials: Int, edgeTrials: Int, edgeSampled: Int)
    case edgeCaseAdvisory(defaultTrials: Int, edge: EdgeCaseDetail)
    case defaultFails(DefaultFailDetail)
    case error(reason: String)

    // A flat 6-arg counterexample constructor naturally takes one param per
    // marker the stub prints; the bundling that satisfies the associated-value
    // limit lives in `DefaultFailDetail`. Waive parameter-count for this one
    // convenience factory (scoped), rather than forcing every call site to
    // build the struct inline.
    // swiftlint:disable function_parameter_count

    /// Flat convenience constructor — keeps call sites ergonomic while the
    /// case itself carries a single bundled `DefaultFailDetail`. The shrink
    /// markers default to "none" so pre-v1.141 / non-shrinking emitters
    /// construct unchanged.
    public static func defaultFails(
        trial: Int,
        input: String,
        forwardResult: String,
        inverseResult: String,
        shrunk: String?,
        shrinkSteps: Int
    ) -> Self {
        let shrink = shrunk.map { ShrinkTrace(minimal: $0, steps: shrinkSteps) }
        return .defaultFails(
            DefaultFailDetail(
                trial: trial,
                input: input,
                forwardResult: forwardResult,
                inverseResult: inverseResult,
                shrink: shrink
            )
        )
    }
    // swiftlint:enable function_parameter_count
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
        let defaultPass = lines.contains { $0.hasPrefix("VERIFY_DEFAULT_RESULT: PASS") }
        let defaultFail = lines.contains { $0.hasPrefix("VERIFY_DEFAULT_RESULT: FAIL") }
        let edgePass = lines.contains { $0.hasPrefix("VERIFY_EDGE_RESULT: PASS") }
        let edgeFail = lines.contains { $0.hasPrefix("VERIFY_EDGE_RESULT: FAIL") }

        if defaultFail, output.exitCode == 1 {
            let trial = Int(value(forMarker: "VERIFY_DEFAULT_TRIAL:", in: lines) ?? "") ?? -1
            let input = value(forMarker: "VERIFY_DEFAULT_INPUT:", in: lines) ?? "(missing)"
            let forwardResult = value(forMarker: "VERIFY_DEFAULT_FORWARD:", in: lines) ?? "(missing)"
            let inverseResult = value(forMarker: "VERIFY_DEFAULT_INVERSE:", in: lines) ?? "(missing)"
            // v1.141: shrink markers are optional — emitters that don't yet
            // ship a shrink phase (or carriers with no shrinker) simply omit
            // them, leaving `shrunk == nil` / `shrinkSteps == 0`.
            let shrunk = value(forMarker: "VERIFY_DEFAULT_SHRUNK:", in: lines)
            let shrinkSteps = Int(value(forMarker: "VERIFY_SHRINK_STEPS:", in: lines) ?? "") ?? 0
            return .defaultFails(
                trial: trial,
                input: input,
                forwardResult: forwardResult,
                inverseResult: inverseResult,
                shrunk: shrunk,
                shrinkSteps: shrinkSteps
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
                edge: EdgeCaseDetail(
                    trial: edgeTrial,
                    input: edgeInput,
                    forward: edgeForward,
                    inverse: edgeInverse,
                    caseIndex: edgeCaseIndex
                )
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
