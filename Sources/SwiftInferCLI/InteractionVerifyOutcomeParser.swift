import Foundation
import SwiftInferCore

/// V2.0 M3.E.3 — parses the verifier subprocess's exit code + stdout
/// into one of the v1.42 five-category outcomes
/// (`VerifyEvidenceOutcome`). The mapping:
///
/// | Subprocess result                            | Outcome                       |
/// |---|---|
/// | exit code 0 + marker line "bothPass totalRuns=N clean=N" | `.measuredBothPass`            |
/// | exit code != 0 (Swift trap)                  | `.measuredDefaultFails`        |
/// | exit code 0 but no marker line               | `.measuredError`               |
/// | build failure (exit code != 0 from `swift build`) | `.architecturalCoveragePending` |
///
/// **Why exit code != 0 → `.measuredDefaultFails` for the runner
/// (but `.architecturalCoveragePending` for the build step).** A
/// non-zero exit from the verifier binary means a Swift trap fired —
/// the reducer panicked under some action sequence, which IS a real
/// signal that the property "reducer doesn't crash" is violated. A
/// non-zero exit from `swift build` means we couldn't even compile
/// the stub — the user's State / Action types don't satisfy the
/// reducer-verify shape (missing `init()`, non-`CaseIterable` Action,
/// etc.), which is the v1.42 `.architecturalCoveragePending` shape
/// "we couldn't run the measurement at all."
///
/// `.measuredEdgeCaseAdvisory` is intentionally unused at M3.0/M3.E
/// — curated edge-case action sequences ship at M5+.
public enum InteractionVerifyOutcomeParser {

    public struct Result: Equatable, Sendable {
        public let outcome: VerifyEvidenceOutcome
        public let totalRuns: Int?
        public let cleanRuns: Int?
        public let detail: String?
        /// V2.0 M8.D.1 — sequence index of the iteration that
        /// trapped, recovered from the stub's stderr trace marker.
        /// `nil` for clean runs, build failures, or non-default-fail
        /// outcomes; also `nil` if the stub trapped before writing
        /// the first marker (e.g., a crash in generator construction).
        public let failingSequenceIndex: Int?

        public init(
            outcome: VerifyEvidenceOutcome,
            totalRuns: Int? = nil,
            cleanRuns: Int? = nil,
            detail: String? = nil,
            failingSequenceIndex: Int? = nil
        ) {
            self.outcome = outcome
            self.totalRuns = totalRuns
            self.cleanRuns = cleanRuns
            self.detail = detail
            self.failingSequenceIndex = failingSequenceIndex
        }
    }

    /// V2.0 M3.E.3 / M8.D.1 — parse the binary-run leg of the
    /// pipeline. Called after `VerifierSubprocess.runSwiftBuild`
    /// returned a non-error exit code (build step succeeded), so
    /// `binaryExitCode == 0` here means "ran cleanly, marker
    /// expected." Non-zero exit code means a trap; M8.D.1 also
    /// scans stderr for the last `TRACE-CURRENT-SEQ:` line so the
    /// caller can replay just the failing sequence.
    public static func parseRunOutput(
        binaryExitCode: Int32,
        stdout: String,
        stderr: String = ""
    ) -> Result {
        if binaryExitCode != 0 {
            let failingIndex = extractFailingSequenceIndex(from: stderr)
            let indexDetail = failingIndex.map { " at sequence index \($0)" } ?? ""
            return Result(
                outcome: .measuredDefaultFails,
                detail: "verifier exited with code \(binaryExitCode)\(indexDetail) "
                    + "— trap in reducer body",
                failingSequenceIndex: failingIndex
            )
        }
        guard let parsed = extractMarker(from: stdout) else {
            return Result(
                outcome: .measuredError,
                detail: "verifier exited cleanly but did not emit the expected outcome marker"
            )
        }
        // Marker present + exit code 0 = bothPass.
        return Result(
            outcome: .measuredBothPass,
            totalRuns: parsed.totalRuns,
            cleanRuns: parsed.cleanRuns,
            detail: "totalRuns=\(parsed.totalRuns) clean=\(parsed.cleanRuns)"
        )
    }

    /// V2.0 M3.E.3 — parse the build leg. A non-zero `swift build`
    /// exit code means the synthesized stub didn't compile against
    /// the user's module — typically a missing `State()` no-arg init
    /// or a non-`CaseIterable` Action. Surface as
    /// `.architecturalCoveragePending` with the last few lines of
    /// stderr in `detail` so the caller can render a helpful error.
    public static func parseBuildFailure(
        buildExitCode: Int32,
        stderr: String
    ) -> Result {
        let snippet = lastLines(stderr, count: 8)
        return Result(
            outcome: .architecturalCoveragePending,
            detail: "swift build failed with exit code \(buildExitCode). "
                + "Last lines of stderr:\n\(snippet)"
        )
    }

    // MARK: - Internals

    struct MarkerFields: Equatable {
        let totalRuns: Int
        let cleanRuns: Int
    }

    /// Look for the `INTERACTION-VERIFY-OUTCOME: bothPass totalRuns=N clean=K`
    /// marker line and extract `(N, K)`. Pure; no I/O. Returns `nil`
    /// when the marker is absent or the trailing numerics don't parse.
    static func extractMarker(from stdout: String) -> MarkerFields? {
        let prefix = ActionSequenceStubEmitter.cleanOutcomeMarker
        for rawLine in stdout.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix(prefix) else { continue }
            let rest = String(line.dropFirst(prefix.count))
            // Expect " totalRuns=<N> clean=<K>"
            let parts = rest.split(separator: " ").filter { !$0.isEmpty }
            var totalRuns: Int?
            var cleanRuns: Int?
            for part in parts {
                if let value = parseAssign(part, key: "totalRuns") {
                    totalRuns = value
                } else if let value = parseAssign(part, key: "clean") {
                    cleanRuns = value
                }
            }
            if let totalRuns, let cleanRuns {
                return MarkerFields(totalRuns: totalRuns, cleanRuns: cleanRuns)
            }
        }
        return nil
    }

    /// `"totalRuns=1024"` → `1024` when `key == "totalRuns"`; `nil`
    /// for any mismatch.
    private static func parseAssign(_ token: Substring, key: String) -> Int? {
        guard token.hasPrefix("\(key)=") else { return nil }
        let valuePart = token.dropFirst(key.count + 1)
        return Int(valuePart)
    }

    /// Tail `n` lines of `text` joined by newlines; useful for surfacing
    /// the most recent stderr lines from a build failure without
    /// dumping the entire `swift build` log.
    private static func lastLines(_ text: String, count: Int) -> String {
        text.split { $0 == "\n" || $0 == "\r" }
            .suffix(count)
            .joined(separator: "\n")
    }

    /// V2.0 M8.D.1 — scan stderr for the last
    /// `TRACE-CURRENT-SEQ: <i>` line and return `<i>`. The stub
    /// prints one such line before each generator step; on trap,
    /// the last successfully written line tells the pipeline which
    /// sequence index trapped (it had begun the iteration but didn't
    /// reach the next iteration's marker). Returns `nil` when no
    /// marker is present — e.g., the stub trapped before the first
    /// iteration, or no stderr was captured.
    static func extractFailingSequenceIndex(from stderr: String) -> Int? {
        let prefix = ActionSequenceStubEmitter.traceCurrentSequenceMarker
        var last: Int?
        for rawLine in stderr.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix(prefix) else { continue }
            let rest = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            if let value = Int(rest) {
                last = value
            }
        }
        return last
    }
}
