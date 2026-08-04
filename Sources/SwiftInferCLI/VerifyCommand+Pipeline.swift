import Foundation
import SwiftInferCore

// V1.142 lint pass — the single-suggestion verify pipeline orchestration,
// split out of `VerifyCommand.swift` (which had hit SwiftLint's 400-line
// file-length cap). The command shell (flags + `run()`) stays in
// `VerifyCommand.swift`; the pipeline steps and the v1.142 auto-bridge
// rendering live here.
extension SwiftInferCommand.Verify {

    /// Orchestration glue. Pure-ish entry point so tests can drive verify
    /// end-to-end without the AsyncParsableCommand shell. Resolves the entry,
    /// emits + builds + runs the verifier workdir, persists evidence, and
    /// renders the outcome (appending the auto-bridge regression-test note
    /// when `emitRegression` and the run found a counterexample).
    static func runPipeline(
        suggestionPrefix: String,
        indexPathOverride: String?,
        budgetString: String,
        workingDirectory: URL,
        emitRegression: Bool = false,
        target: String? = nil
    ) throws -> String {
        let packageRoot = findPackageRoot(startingFrom: workingDirectory)
            ?? workingDirectory
        let resolved = try resolveEntry(
            suggestionPrefix: suggestionPrefix,
            indexPathOverride: indexPathOverride,
            packageRoot: packageRoot
        )
        let entry = resolved.entry
        // V1.149 — path-depend on the user package and `@testable`-import the module, so the
        // stub can call functions defined there (incl. `internal`). Absent `--target`, the module
        // is DERIVED from the entry's own source path: the flag was optional and its absence
        // silent, so the common gesture — `verify --suggestion <hash>` — reached none of the
        // user's own code and failed to build. See `VerifyCommand+Wiring`.
        let wiring = Self.wiring(for: resolved, explicitTarget: target, packageRoot: packageRoot)
        let stubBundle = try Self.buildStubBundle(
            entry: entry,
            budget: parseBudget(budgetString),
            extraImports: wiring.extraImports,
            allShapes: resolved.allShapes
        )
        let workdir = packageRoot
            .appendingPathComponent(".swiftinfer")
            .appendingPathComponent("verify-workdir")
            .appendingPathComponent(workdirSegment(for: entry.identityHash))
        _ = try VerifierWorkdir.synthesize(
            VerifierWorkdir.Inputs(
                workdir: workdir,
                userPackage: wiring.userPackage,
                stubSource: stubBundle.source
            )
        )
        let runOutput = try buildAndRun(workdir: workdir)
        let parsed = VerifyResultParser.parse(runOutput)
        // V1.142 — emit the regression test once; its path feeds both the
        // persisted evidence and the rendered output note.
        let regressionPath: URL? = {
            guard emitRegression, case let .defaultFails(detail) = parsed else { return nil }
            return emitRegressionTest(entry: entry, detail: detail, packageRoot: packageRoot)
        }()
        persistEvidence(
            parsed: parsed,
            entry: entry,
            packageRoot: packageRoot,
            regressionPath: regressionPath
        )
        persistCorpus(parsed: parsed, entry: entry, packageRoot: packageRoot)
        return renderOutcome(
            parsed: parsed,
            context: stubBundle.rendererContext,
            entry: entry,
            packageRoot: packageRoot,
            regressionPath: regressionPath
        )
    }

    /// V1.142 — the verify stub's replayable seed (deterministic Xoshiro state
    /// derived from the identity hash), serialized as colon-joined hex for the
    /// v1.143 replay corpus.
    static func seedString(for identityHash: String) -> String {
        let seed = makeSeedHex(from: identityHash)
        return [seed.stateA, seed.stateB, seed.stateC, seed.stateD]
            .map { String($0, radix: 16) }
            .joined(separator: ":")
    }

    /// Package-relative display path (falls back to the absolute path when the
    /// URL isn't under `packageRoot`).
    static func packageRelative(_ url: URL, packageRoot: URL) -> String {
        let prefix = packageRoot.path + "/"
        return url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.path
    }

    /// V1.64.B — persist the outcome to `.swiftinfer/verify-evidence.json` so
    /// `discover` can annotate this suggestion later. Best-effort: a
    /// persistence failure warns on stderr but never fails the verify gesture.
    /// `now` is injected (defaulting to the wall clock) so a test can pin the
    /// stamp — SwiftProjectLint's Non-Injected Nondeterminism rule. The stamp is
    /// persisted at whole-second `.iso8601` resolution, and two records tying on
    /// it are exactly what makes the log `merge` folds non-commutative (see
    /// `MergeAlgebraPropertyTests`).
    private static func persistEvidence(
        parsed: VerifyOutcome,
        entry: SemanticIndexEntry,
        packageRoot: URL,
        regressionPath: URL?,
        now: Date = Date()
    ) {
        let (evidenceOutcome, evidenceDetail) = VerifyEvidenceRecorder.evidence(for: parsed)
        // V1.142 — capture the counterexample / shrunk minimal / replay seed
        // for default-fail runs so the v1.143 corpus + discover annotations
        // don't need to re-run verify.
        var counterexample: String?
        var shrunkCounterexample: String?
        var seed: String?
        if case let .defaultFails(detail) = parsed {
            counterexample = detail.input
            shrunkCounterexample = detail.shrink?.minimal
            seed = seedString(for: entry.identityHash)
        }
        let recordWarnings = VerifyEvidenceRecorder.record(
            VerifyEvidence(
                identityHash: VerifyEvidenceRecorder.normalizedIdentityHash(entry.identityHash),
                template: entry.templateName,
                outcome: evidenceOutcome,
                detail: evidenceDetail,
                capturedAt: now,
                swiftInferVersion: VerifyEvidenceRecorder.swiftInferVersion,
                counterexample: counterexample,
                shrunkCounterexample: shrunkCounterexample,
                seed: seed,
                regressionTestPath: regressionPath.map { packageRelative($0, packageRoot: packageRoot) }
            ),
            packageRoot: packageRoot
        )
        for warning in recordWarnings {
            FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
        }
    }

    /// V1.143 — accumulate a found counterexample into the durable replay
    /// corpus (`.swiftinfer/verify-corpus.json`) so it's re-checked on every
    /// run as a permanent regression guard. Best-effort; only default-fails
    /// record. (Single-suggestion path; survey-mode batching is a follow-on.)
    /// `now` is injected (defaulting to the wall clock) so a test can pin the
    /// stamp — SwiftProjectLint's Non-Injected Nondeterminism rule.
    private static func persistCorpus(
        parsed: VerifyOutcome,
        entry: SemanticIndexEntry,
        packageRoot: URL,
        now: Date = Date()
    ) {
        guard case let .defaultFails(detail) = parsed else { return }
        let record = VerifyCorpusEntry(
            identityHash: VerifyEvidenceRecorder.normalizedIdentityHash(entry.identityHash),
            template: entry.templateName,
            counterexample: detail.input,
            shrunkCounterexample: detail.shrink?.minimal,
            seed: seedString(for: entry.identityHash),
            capturedAt: now,
            swiftInferVersion: VerifyEvidenceRecorder.swiftInferVersion
        )
        for warning in VerifyCorpusStore.record(record, packageRoot: packageRoot) {
            FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
        }
    }

    /// V1.144 — render the outcome and, for a counterexample, append the
    /// unified failure block: the auto-bridge regression-test path (written
    /// upstream), the replayable seed, and the corpus + replay-gate hints — so
    /// the developer sees the whole loop (minimal counterexample → durable test
    /// → replay) in one place. Non-failures render unchanged.
    static func renderOutcome(
        parsed: VerifyOutcome,
        context: VerifyResultRenderer.Context,
        entry: SemanticIndexEntry,
        packageRoot: URL,
        regressionPath: URL?
    ) -> String {
        var rendered = VerifyResultRenderer.render(parsed, context: context)
        guard case .defaultFails = parsed else { return rendered }
        if let regressionPath {
            rendered += "\n    regression test → \(packageRelative(regressionPath, packageRoot: packageRoot))"
        }
        rendered += "\n    seed: \(seedString(for: entry.identityHash))"
        let corpusCount = VerifyCorpusStore.load(packageRoot: packageRoot).corpus.entries.count
        let prefix = String(entry.identityHash.prefix(10))
        rendered += "\n    corpus: \(corpusCount) recorded"
            + " · re-verify: swift-infer verify --suggestion \(prefix)"
            + " · gate: swift-infer verify --replay-only"
        return rendered
    }

    /// Sub-step: load the SemanticIndex + look up the suggestion by prefix.
    /// Surfaces stale-index / lookup warnings on stderr; returns the entry.
    private static func resolveEntry(
        suggestionPrefix: String,
        indexPathOverride: String?,
        packageRoot: URL,
        clockNow: Date = Date()
    ) throws -> ResolvedEntry {
        // Injected via `now` so a test can pin it (SwiftProjectLint's
        // Non-Injected Nondeterminism rule). Only feeds `IndexStore.load`'s
        // `.empty(at:)` staleness fallback, so any stable value works.
        let now = ISO8601DateFormatter().string(from: clockNow)
        let explicitIndexPath = indexPathOverride.map { URL(fileURLWithPath: $0) }
        try reindexIfNeeded(packageRoot: packageRoot, explicitIndexPath: explicitIndexPath)
        let resolved = try VerifyHarness.resolveIndex(
            packageRoot: packageRoot,
            explicitIndexPath: explicitIndexPath,
            now: now
        )
        let lookup = try VerifyHarness.lookupSuggestion(
            hashPrefix: suggestionPrefix,
            in: resolved.index,
            staleWarnings: resolved.warnings,
            indexPath: resolved.path
        )
        for warning in lookup.warnings {
            FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
        }
        // WS-6 Slice 2 — carry the whole-module shape universe alongside the
        // matched entry so verify can recursively derive nested custom-type
        // carriers. Empty on un-reindexed (pre-v4) indexes → no recursion.
        // `sourceFileByTypeName` rides alongside for the same reason: verify must resolve the
        // module of every type the carrier reaches, not just the one on the entry.
        return ResolvedEntry(
            entry: lookup.entry,
            allShapes: resolved.index.typeShapes,
            sourceFiles: resolved.index.sourceFileByTypeName
        )
    }

    /// Sub-step: build the synthesized workdir and run the verifier binary.
    /// Build failures surface as `.buildFailed`; the captured run output is
    /// returned for the parser to consume.
    private static func buildAndRun(workdir: URL) throws -> VerifierSubprocess.Output {
        let buildOutput = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
        guard buildOutput.exitCode == 0 else {
            throw VerifyError.buildFailed(
                exitCode: buildOutput.exitCode,
                stderr: BuildDiagnostics.summary(from: buildOutput)
            )
        }
        return try VerifierSubprocess.runVerifierBinary(workdir: workdir)
    }
}
