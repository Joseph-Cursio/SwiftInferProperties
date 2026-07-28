import Foundation

/// Extracts the compiler's actual diagnosis from a failed `swift build`.
///
/// **`swift build` writes compile errors to stdout, not stderr.** Measured on
/// the road-test workdir: exit 1, 235 `error:` lines on stdout, zero bytes on
/// stderr. Both build-failure paths read only stderr, so every failure was
/// reported as `Last 20 lines of stderr:` followed by nothing, and survey mode
/// as `build-failed: exit=1` with no detail whatsoever.
///
/// That is why one entry cost three investigations and read as three different
/// problems (`docs/roadtest-self-dogfood.md` §13.4). The evidence was captured
/// and discarded at the last step, and "(no stderr captured)" reads as *the
/// compiler said nothing* rather than *we looked in the wrong place*.
///
/// Two choices here are deliberate:
///
///   - **Whichever stream carries `error:` wins**, rather than swapping stdout
///     for stderr. A toolchain that changes its mind about streams should not
///     break this again.
///   - **Located errors beat a positional tail.** A 235-line build log ends in
///     `error: fatalError` and `Build failed`, neither of which names a cause;
///     the first located `file:line: error:` lines do.
public enum BuildDiagnostics {

    /// Compiler errors from a failed build, newline-joined, or a tail if the
    /// output has no `error:` lines at all (a linker or toolchain failure still
    /// deserves its output).
    public static func summary(from output: VerifierSubprocess.Output, limit: Int = 5) -> String {
        let candidates = [output.stderr, output.stdout].filter { !$0.isEmpty }
        guard !candidates.isEmpty else { return "(none captured)" }

        for stream in candidates {
            let errors = locatedErrors(in: stream)
            if !errors.isEmpty { return errors.prefix(limit).joined(separator: "\n") }
        }
        // No `error:` anywhere — fall back to the tail of the first non-empty
        // stream rather than reporting nothing.
        let lines = candidates[0].split(separator: "\n").map(String.init)
        return lines.suffix(limit).joined(separator: "\n")
    }

    /// One-line, bounded form for a survey record, which is a single JSON line
    /// per entry. `build-failed: exit=1` was the whole detail before — and the
    /// exit code is the least informative part of a build failure, being
    /// always 1.
    public static func surveyDetail(
        from output: VerifierSubprocess.Output,
        maxLength: Int = 300
    ) -> String {
        let cause = summary(from: output, limit: 2)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " | ")
        let detail = "build-failed: exit=\(output.exitCode): \(cause)"
        guard detail.count > maxLength else { return detail }
        return String(detail.prefix(maxLength - 1)) + "…"
    }

    /// Lines carrying a located compiler error (`file:line:col: error: …`),
    /// de-duplicated.
    ///
    /// SwiftPM prints each diagnostic twice — once plainly and once inside an
    /// ASCII source-context frame (`| \`- error: …`). Keeping only lines whose
    /// `error:` is preceded by a `:`-separated location drops the frame copy
    /// and the bare `error: fatalError` summary in one rule.
    private static func locatedErrors(in stream: String) -> [String] {
        var seen: Set<String> = []
        return stream.split(separator: "\n").map(String.init).filter { line in
            guard let range = line.range(of: ": error: ") else { return false }
            let location = line[line.startIndex ..< range.lowerBound]
            guard location.contains(":"), !location.contains("`-") else { return false }
            return seen.insert(line.trimmingCharacters(in: .whitespaces)).inserted
        }
    }
}
