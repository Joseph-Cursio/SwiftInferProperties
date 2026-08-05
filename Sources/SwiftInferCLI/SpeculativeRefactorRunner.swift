import Foundation
import SwiftInferCore

/// Copy the tree, widen one access modifier, discover what became visible, and
/// report the law with its verdict — the `--speculative` half of
/// `suggest-refactors`.
///
/// ## The inversion, and why it is gated
///
/// `prove-then-show` hides `Possible` suggestions until a law has run. This is the
/// same move applied to refactor advice: the reader is shown *"apply this diff and
/// you get this law, which held over N trials"* rather than *"extract this"*.
///
/// The cost is why it is opt-in and candidate-capped. Every candidate is its own
/// package snapshot plus a verify workdir, and an 85-entry survey already left
/// 3.4 GB behind. This is not something to run by default, and nothing here runs
/// unless `--speculative` is passed.
///
/// ## What it never does
///
/// It does not modify the reader's tree. The widening is applied to a **copy**,
/// and what comes back is a diff — which is what every refactoring tool does, and
/// keeps the repo's standing "never applies anything" line intact.
enum SpeculativeRefactorRunner {

    struct Options {
        let packageRoot: URL
        let maxCandidates: Int
        let budget: String
    }

    /// Run the whole tier-1 loop and return one proposal per candidate examined.
    ///
    /// Returns a proposal even when no law was gained or the law could not run —
    /// **a `noLawGained` row is information**, and suppressing it would make the
    /// command look more effective than it is. Measured 2026-08-04: 14 of 20
    /// widenings gained nothing at all.
    static func run(
        options: Options,
        diagnostics: any DiagnosticOutput = PrintDiagnosticOutput()
    ) throws -> [SpeculativeProposal] {
        let sources = options.packageRoot.appendingPathComponent("Sources")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw SpeculativeRefactorError.noSourcesDirectory(options.packageRoot.path)
        }

        let scan = scanRestricted(under: sources)
        let candidates = Array(
            SpeculativeWidening.candidates(from: scan.restricted, in: scan.sourcesByFile)
                .prefix(options.maxCandidates)
        )
        guard !candidates.isEmpty else { return [] }
        diagnostics.writeDiagnostic(
            "speculative: \(candidates.count) widenable candidate(s) "
                + "(capped at \(options.maxCandidates)); each one costs a package snapshot"
        )

        let baseline = try identities(of: sources)
        return candidates.compactMap { candidate in
            proposal(
                for: candidate,
                baseline: baseline,
                options: options,
                sourcesByFile: scan.sourcesByFile,
                diagnostics: diagnostics
            )
        }
    }

    /// One candidate, end to end.
    private static func proposal(
        for candidate: SpeculativeWidening.Candidate,
        baseline: Set<String>,
        options: Options,
        sourcesByFile: [String: String],
        diagnostics: any DiagnosticOutput
    ) -> SpeculativeProposal? {
        let path = candidate.summary.location.file
        guard let original = sourcesByFile[path],
              let widened = SpeculativeWidening.widened(source: original, candidate: candidate)
        else { return nil }

        let digest = Self.digest(of: original)
        let diff = SpeculativeWidening.unifiedDiff(
            path: relative(path, to: options.packageRoot),
            original: original,
            widened: widened,
            line: candidate.line
        )
        guard let snapshot = try? snapshotTree(of: options.packageRoot, replacing: path, with: widened)
        else { return nil }
        defer { try? FileManager.default.removeItem(at: snapshot.root) }

        let gained = ((try? identities(of: snapshot.sources)) ?? []).subtracting(baseline)
        guard !gained.isEmpty else {
            return SpeculativeProposal(
                path: relative(path, to: options.packageRoot),
                diff: diff,
                sourceDigest: digest,
                lawDescription: "no law became visible",
                verdict: .noLawGained,
                detail: "widening \(candidate.summary.name) exposed the symbol but no template "
                    + "proposed a law — the TEMPLATE gate decides this, not the parameter types"
            )
        }
        diagnostics.writeDiagnostic(
            "speculative: \(candidate.summary.name) gained \(gained.count) law(s); verifying"
        )
        return verified(
            gained: gained,
            snapshot: snapshot,
            patch: .init(path: relative(path, to: options.packageRoot), diff: diff, digest: digest)
        )
    }

    /// Digest of the file as it was READ, so a reader whose source has since moved
    /// can tell the verdict is stale. The copy is a border claim: measured against
    /// a snapshot, reported about the original.
    static func digest(of source: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in source.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return "fnv1a:" + String(hash, radix: 16)
    }

    static func relative(_ path: String, to root: URL) -> String {
        let prefix = root.path + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }
}

enum SpeculativeRefactorError: Error, CustomStringConvertible {
    case noSourcesDirectory(String)

    var description: String {
        switch self {
        case let .noSourcesDirectory(path):
            return "speculative refactoring needs a Sources/ directory to snapshot — none at \(path)"
        }
    }
}
