import ArgumentParser
import Foundation
import SwiftInferCore

extension SwiftInferCommand.Verify {

    /// V1.143.B — corpus-first replay (regression gate). Re-verifies every
    /// suggestion that has a recorded counterexample in
    /// `.swiftinfer/verify-corpus.json` and classifies each: still-failing,
    /// now-holding, inconclusive, or skipped (no longer in the index). Because
    /// the verify seed is deterministic from the identity hash, re-verifying an
    /// identity reproduces its recorded counterexample when the property is
    /// still broken, or passes once it's fixed. Exits non-zero if any recorded
    /// counterexample still fails — a CI guard that stays red until the known
    /// bugs are fixed, then green forever (catching any later regression).
    static func runReplayOnly(
        indexPathOverride: String?,
        budgetString: String,
        workingDirectory: URL
    ) async throws {
        let packageRoot = findPackageRoot(startingFrom: workingDirectory) ?? workingDirectory
        let corpus = VerifyCorpusStore.load(packageRoot: packageRoot).corpus
        guard corpus.entries.isEmpty == false else {
            print(
                "verify --replay-only: no recorded counterexamples in "
                    + VerifyCorpusStore.conventionalRelativePath
            )
            return
        }
        let corpusIdentities = Set(corpus.entries.map(\.identityHash))
        let index = try loadIndex(indexPathOverride: indexPathOverride, packageRoot: packageRoot)
        let config = SurveyConfig(
            budget: parseBudget(budgetString),
            corpusModuleName: nil,
            corpusProductName: nil,
            emitRegression: false
        )

        var lines: [ReplayReport.Line] = []
        var matched: Set<String> = []
        for entry in index.entries {
            let normalized = VerifyEvidenceRecorder.normalizedIdentityHash(entry.identityHash)
            guard corpusIdentities.contains(normalized) else { continue }
            matched.insert(normalized)
            let record = surveyRecord(for: entry, packageRoot: packageRoot, config: config)
            lines.append(
                ReplayReport.Line(
                    identityHash: normalized,
                    template: entry.templateName,
                    status: ReplayReport.status(for: record.outcome),
                    detail: record.outcomeDetail
                )
            )
        }
        // Recorded identities with no current index entry — can't re-verify.
        for skipped in corpusIdentities.subtracting(matched).sorted() {
            lines.append(
                ReplayReport.Line(
                    identityHash: skipped,
                    template: corpus.entries(for: skipped).first?.template ?? "(unknown)",
                    status: .skipped,
                    detail: "no current index entry"
                )
            )
        }
        let report = ReplayReport(lines: lines)
        print(report.render())
        if report.hasRegressions { throw ExitCode.failure }
    }
}

/// V1.143.B — pure, testable replay outcome. Hoisted to file scope (the
/// `nesting` lint rule caps at one level and `Verify` is already nested in
/// `SwiftInferCommand`).
struct ReplayReport {

    enum Status: String {
        case stillFailing
        case nowHolds
        case inconclusive
        case skipped
    }

    struct Line {
        let identityHash: String
        let template: String
        let status: Status
        let detail: String?
    }

    let lines: [Line]

    /// Map a re-verify outcome to a replay status. A recorded counterexample
    /// that still fails is a present bug; a now-passing one means the property
    /// was fixed (the corpus entry is holding); error / coverage-pending are
    /// inconclusive (the run couldn't render a verdict).
    static func status(for outcome: SwiftInferCommand.Verify.SurveyOutcome) -> Status {
        switch outcome {
        case .measuredDefaultFails: return .stillFailing
        case .measuredBothPass, .measuredEdgeCaseAdvisory: return .nowHolds
        case .measuredError, .architecturalCoveragePending: return .inconclusive
        }
    }

    func count(_ status: Status) -> Int { lines.filter { $0.status == status }.count }

    /// The CI gate: red while any recorded counterexample still fails.
    var hasRegressions: Bool { count(.stillFailing) > 0 }

    func render() -> String {
        var out = [
            "verify --replay-only: \(lines.count) recorded counterexample(s)",
            "  ✓ now holds: \(count(.nowHolds))   ✗ still failing: \(count(.stillFailing))"
                + "   ? inconclusive: \(count(.inconclusive))   – skipped: \(count(.skipped))"
        ]
        for line in lines.sorted(by: { $0.identityHash < $1.identityHash }) {
            let suffix = line.detail.map { " — \($0)" } ?? ""
            out.append("    \(Self.glyph(line.status)) \(line.identityHash) [\(line.template)]\(suffix)")
        }
        return out.joined(separator: "\n")
    }

    private static func glyph(_ status: Status) -> String {
        switch status {
        case .stillFailing: return "✗"
        case .nowHolds: return "✓"
        case .inconclusive: return "?"
        case .skipped: return "–"
        }
    }
}
