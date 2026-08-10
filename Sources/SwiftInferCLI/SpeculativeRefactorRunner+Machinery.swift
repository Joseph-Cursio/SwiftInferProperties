import Foundation
import SwiftInferCore

/// The copy-mutate-verify machinery. Split from the runner's policy half both for
/// the file-length cap and because this is the part the design says **later tiers
/// reuse** — closure extraction and kernel extraction differ only in the mutation,
/// not in the snapshot, the discover diff, or the verify hop.
extension SpeculativeRefactorRunner {

    struct Snapshot {
        let root: URL
        let sources: URL
    }

    /// Everything the scan set aside, plus the file contents, read once.
    struct RestrictedScan {
        let restricted: [RestrictedFunction]
        let sourcesByFile: [String: String]
    }

    /// - Parameter diagnostic: reports a source file that could not be read.
    ///
    /// **A dropped file shrinks the candidate population silently.** Its restricted functions
    /// are never proposed for widening, and its path is absent from `sourcesByFile`, which
    /// makes the caller's `guard let original = sourcesByFile[path]` drop the candidate a
    /// second time. Two silent exits for one unreadable file.
    static func scanRestricted(
        under sources: URL,
        diagnostic: (String) -> Void = { _ in /* no-op */ }
    ) -> RestrictedScan {
        var restricted: [RestrictedFunction] = []
        var sourcesByFile: [String: String] = [:]
        for url in swiftFiles(under: sources) {
            let text: String
            do {
                text = try String(contentsOf: url, encoding: .utf8)
            } catch {
                diagnostic(
                    "warning: could not read \(url.lastPathComponent) while scanning for "
                        + "widening candidates — \(error). Any restricted function it "
                        + "declares is absent from this run, not judged."
                )
                continue
            }
            sourcesByFile[url.path] = text
            restricted.append(contentsOf: FunctionScanner.scanCorpus(source: text, file: url.path).restricted)
        }
        return RestrictedScan(restricted: restricted, sourcesByFile: sourcesByFile)
    }

    /// Suggestion identities visible from a `Sources/` tree.
    ///
    /// Identities, not counts: the question is *which* laws appeared, and a count
    /// would answer "how many" while silently tolerating one law replacing another.
    /// `--include-possible` is on because a widened `private` helper lands at
    /// `Possible` far more often than not — 2026-08-04 measured every gained law
    /// there.
    static func identities(of sources: URL) throws -> Set<String> {
        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: sources,
            includePossible: true,
            diagnostics: SilentDiagnostics()
        )
        return Set(result.suggestions.map(\.identity.display))
    }

    /// Copy the package to a temporary tree with one file replaced.
    ///
    /// A full copy rather than a symlink farm or an overlay, because verify
    /// path-depends on the package and builds it: anything that leaves the
    /// original reachable risks compiling the reader's real code and reporting a
    /// verdict about a patch that was never applied.
    static func snapshotTree(
        of packageRoot: URL,
        replacing path: String,
        with contents: String
    ) throws -> Snapshot {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swiftinfer-speculative-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // Sources + manifest only. `.build` is the reason this is a whitelist and
        // not a blanket copy — it is gigabytes, and copying it would make the
        // per-candidate cost prohibitive rather than merely high.
        for item in ["Package.swift", "Sources"] {
            let from = packageRoot.appendingPathComponent(item)
            guard FileManager.default.fileExists(atPath: from.path) else { continue }
            try FileManager.default.copyItem(at: from, to: root.appendingPathComponent(item))
        }
        let mirrored = root.appendingPathComponent(relative(path, to: packageRoot))
        try contents.write(to: mirrored, atomically: true, encoding: .utf8)
        return Snapshot(root: root, sources: root.appendingPathComponent("Sources"))
    }

    /// Verify the gained laws against the snapshot and fold them into one verdict.
    ///
    /// **The first law that RUNS decides the verdict**, and a refutation outranks a
    /// hold. A patch that unlocks one true law and one false one is not a
    /// recommendation — the reader would apply it and inherit a failing test.
    ///
    /// Routed through `surveyRecord`, which returns a `SurveyOutcome` **enum**,
    /// rather than through `runPipeline`, which returns prose for a human. The
    /// first version matched `runPipeline`'s output for the string `"bothPass"` —
    /// a word it never emits, since it renders `"✓ verify holds (strong): …"`. So
    /// every candidate reported `lawNotRunnable` and the headline outcome was
    /// unreachable. Caught only by running the thing end to end on a fixture built
    /// to hold; the unit tests could not see it.
    /// The unchanging half of a proposal — everything known before a law runs.
    struct PatchContext {
        let path: String
        let diff: String
        let digest: String
    }

    static func verified(
        gained: Set<String>,
        snapshot: Snapshot,
        patch: PatchContext
    ) -> SpeculativeProposal {
        let (path, diff, digest) = (patch.path, patch.diff, patch.digest)
        let entries = (try? SwiftInferCommand.Verify.loadIndex(
            indexPathOverride: nil, packageRoot: snapshot.root
        ))?.entries ?? []
        let config = SwiftInferCommand.Verify.SurveyConfig(
            budget: RoundTripStubEmitter.TrialBudget.small,
            corpusModuleName: nil,
            corpusProductName: nil,
            emitRegression: false
        )
        var firstHeld: SpeculativeProposal?
        for entry in entries.filter({ gained.contains($0.identityHash) }).sorted(by: {
            $0.identityHash < $1.identityHash
        }) {
            let record = SwiftInferCommand.Verify.surveyRecord(
                for: entry, packageRoot: snapshot.root, config: config
            )
            let law = "\(entry.templateName) on \(entry.typeName ?? "?").\(entry.primaryFunctionName)"
            switch record.outcome {
            case .measuredDefaultFails:
                return SpeculativeProposal(
                    path: path, diff: diff, sourceDigest: digest, lawDescription: law,
                    verdict: .lawRefutedOnPatchedCopy,
                    detail: "the law is false of this function — applying the patch would give "
                        + "you a failing test. Measured 2026-08-04, both refutations of this "
                        + "shape were `idempotence` on a non-idempotent `T -> T`, not bugs"
                )

            case .measuredBothPass, .measuredEdgeCaseAdvisory:
                if firstHeld == nil {
                    firstHeld = SpeculativeProposal(
                        path: path, diff: diff, sourceDigest: digest, lawDescription: law,
                        verdict: .lawHeldOnPatchedCopy,
                        detail: "held on the patched copy (\(record.outcomeDetail ?? "")) — "
                            + "apply the diff to get this law"
                    )
                }

            case .measuredError, .architecturalCoveragePending:
                continue
            }
        }
        return firstHeld ?? SpeculativeProposal(
            path: path, diff: diff, sourceDigest: digest,
            lawDescription: "\(gained.count) law(s) proposed, none executable",
            verdict: .lawNotRunnable,
            detail: "no generator for the carrier, no composer, or the stub did not build — "
                + "not evidence about the refactor either way"
        )
    }

    static func swiftFiles(under root: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { return [] }
        return walker.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
    }
}

/// Discover writes progress to stderr; a speculative run does it once per
/// candidate and the noise would bury the proposals.
struct SilentDiagnostics: DiagnosticOutput {
    func writeDiagnostic(_: String) { /* deliberately silent */ }
}

extension SpeculativeRefactorRunner {

    /// Snapshot the tree, or report why not and skip the candidate.
    ///
    /// Was `try? … else { return nil }` inline, which dropped the candidate with no trace —
    /// indistinguishable from a candidate that was never proposed at all.
    static func snapshotOrReport(
        packageRoot: URL,
        path: String,
        widened: String,
        candidate: SpeculativeWidening.Candidate,
        diagnostics: any DiagnosticOutput
    ) -> Snapshot? {
        do {
            return try snapshotTree(of: packageRoot, replacing: path, with: widened)
        } catch {
            diagnostics.writeDiagnostic(
                "warning: speculative: could not snapshot the tree for "
                    + "\(candidate.summary.name) — \(error). This candidate is skipped, not "
                    + "judged: it is absent from the results rather than reported as gaining "
                    + "nothing."
            )
            return nil
        }
    }

    /// Read the laws visible in a widened tree, or report why not and skip the candidate.
    ///
    /// **An error here used to become a VERDICT.** `(try? …) ?? []` made the gained set empty,
    /// and the caller then reported `.noLawGained` with the detail *"widening exposed the
    /// symbol but no template proposed a law — the TEMPLATE gate decides this"*. That sentence
    /// asserts a specific mechanism, and an I/O or parse failure produced it verbatim. A wrong
    /// explanation is worse than no result: it is actionable in the wrong direction, sending a
    /// reader to inspect the template gate for a read failure.
    static func identitiesOrReport(
        sources: URL,
        candidate: SpeculativeWidening.Candidate,
        diagnostics: any DiagnosticOutput
    ) -> Set<String>? {
        do {
            return try identities(of: sources)
        } catch {
            diagnostics.writeDiagnostic(
                "warning: speculative: could not read laws from the widened tree for "
                    + "\(candidate.summary.name) — \(error). This candidate is skipped, not "
                    + "judged — reporting `no law became visible` here would blame the "
                    + "template gate for a read failure."
            )
            return nil
        }
    }
}
