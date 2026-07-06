/// Renders `ValueSemanticVerifier` results into a human-readable report.
/// Pure + byte-stable (each group sorted by location then name) so it is
/// unit-testable without a subprocess. Polarity-correct: confirmed leaks lead.
public enum ValueSemanticVerifyReport {

    /// `true` when any result is a confirmed leak — the `--fail-on-leak` gate.
    public static func leaksFound(in results: [ValueSemanticVerifyResult]) -> Bool {
        results.contains(where: \.isConfirmedLeak)
    }

    public static func render(results: [ValueSemanticVerifyResult], moduleName: String) -> String {
        guard !results.isEmpty else {
            return "swift-infer verify-value-semantics: no value-semantics "
                + "candidates found in \(moduleName).\n"
        }

        let leaks = filter(results) {
            if case .confirmedLeak = $0 { return true }
            return false
        }
        let safe = filter(results) { $0 == .verifiedSafe }
        let skipped = filter(results) {
            if case .notVerifiable = $0 { return true }
            return false
        }
        let errors = filter(results) {
            if case .buildFailed = $0 { return true }
            if case .error = $0 { return true }
            return false
        }

        var lines: [String] = [
            "swift-infer verify-value-semantics — \(results.count) candidate"
                + "\(results.count == 1 ? "" : "s") in \(moduleName):",
            ""
        ]
        appendLeaks(leaks, into: &lines)
        appendSection("\u{2713}  Verified value-semantic", safe, into: &lines) { _ in nil }
        appendSection("\u{2298}  Not verifiable", skipped, into: &lines) { status in
            if case .notVerifiable(let reason) = status { return reason }
            return nil
        }
        appendSection("\u{2717}  Build / verify errors", errors, into: &lines) { status in
            switch status {
            case .buildFailed(let detail): return detail
            case .error(let reason): return reason
            default: return nil
            }
        }
        lines.append(summary(leaks: leaks.count, safe: safe.count, skipped: skipped.count, errors: errors.count))
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Sections

    private static func appendLeaks(_ leaks: [ValueSemanticVerifyResult], into lines: inout [String]) {
        guard !leaks.isEmpty else { return }
        lines.append("\u{26A0}  CONFIRMED LEAKS (\(leaks.count))")
        for result in leaks {
            lines.append("  \(origin(result))  \(result.typeName)")
            if case .confirmedLeak(let repro) = result.status {
                lines.append("      \(repro)")
            }
        }
        lines.append("")
    }

    private static func appendSection(
        _ heading: String,
        _ group: [ValueSemanticVerifyResult],
        into lines: inout [String],
        detail: (ValueSemanticVerifyResult.Status) -> String?
    ) {
        guard !group.isEmpty else { return }
        lines.append("\(heading) (\(group.count))")
        for result in group {
            if let note = detail(result.status) {
                lines.append("  \(origin(result))  \(result.typeName) — \(note)")
            } else {
                lines.append("  \(origin(result))  \(result.typeName)")
            }
        }
        lines.append("")
    }

    private static func summary(leaks: Int, safe: Int, skipped: Int, errors: Int) -> String {
        let total = leaks + safe + skipped + errors
        var parts = ["\(total) candidate\(total == 1 ? "" : "s")", "\(leaks) leak\(leaks == 1 ? "" : "s")"]
        parts.append("\(safe) safe")
        parts.append("\(skipped) skipped")
        if errors > 0 { parts.append("\(errors) error\(errors == 1 ? "" : "s")") }
        return "Summary: " + parts.joined(separator: " \u{00B7} ")
    }

    // MARK: - Helpers

    private static func filter(
        _ results: [ValueSemanticVerifyResult],
        _ matches: (ValueSemanticVerifyResult.Status) -> Bool
    ) -> [ValueSemanticVerifyResult] {
        results
            .filter { matches($0.status) }
            .sorted { (origin($0), $0.typeName) < (origin($1), $1.typeName) }
    }

    private static func origin(_ result: ValueSemanticVerifyResult) -> String {
        "\(result.location.file):\(result.location.line)"
    }
}
