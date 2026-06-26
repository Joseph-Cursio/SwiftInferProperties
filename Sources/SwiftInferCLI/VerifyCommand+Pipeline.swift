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
        emitRegression: Bool = false
    ) throws -> String {
        let packageRoot = findPackageRoot(startingFrom: workingDirectory)
            ?? workingDirectory
        let entry = try resolveEntry(
            suggestionPrefix: suggestionPrefix,
            indexPathOverride: indexPathOverride,
            packageRoot: packageRoot
        )
        let stubBundle = try Self.buildStubBundle(
            entry: entry,
            budget: parseBudget(budgetString)
        )
        let workdir = packageRoot
            .appendingPathComponent(".swiftinfer")
            .appendingPathComponent("verify-workdir")
            .appendingPathComponent(workdirSegment(for: entry.identityHash))
        _ = try VerifierWorkdir.synthesize(
            VerifierWorkdir.Inputs(
                workdir: workdir,
                userPackage: nil,
                stubSource: stubBundle.source
            )
        )
        let runOutput = try buildAndRun(workdir: workdir)
        let parsed = VerifyResultParser.parse(runOutput)
        persistEvidence(parsed: parsed, entry: entry, packageRoot: packageRoot)
        return renderWithRegression(
            parsed: parsed,
            context: stubBundle.rendererContext,
            entry: entry,
            packageRoot: packageRoot,
            emitRegression: emitRegression
        )
    }

    /// V1.64.B — persist the outcome to `.swiftinfer/verify-evidence.json` so
    /// `discover` can annotate this suggestion later. Best-effort: a
    /// persistence failure warns on stderr but never fails the verify gesture.
    private static func persistEvidence(
        parsed: VerifyOutcome,
        entry: SemanticIndexEntry,
        packageRoot: URL
    ) {
        let (evidenceOutcome, evidenceDetail) = VerifyEvidenceRecorder.evidence(for: parsed)
        let recordWarnings = VerifyEvidenceRecorder.record(
            VerifyEvidence(
                identityHash: VerifyEvidenceRecorder.normalizedIdentityHash(entry.identityHash),
                template: entry.templateName,
                outcome: evidenceOutcome,
                detail: evidenceDetail,
                capturedAt: Date(),
                swiftInferVersion: VerifyEvidenceRecorder.swiftInferVersion
            ),
            packageRoot: packageRoot
        )
        for warning in recordWarnings {
            FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
        }
    }

    /// V1.142 — render the outcome and, when `emitRegression` is set and the
    /// run found a counterexample, auto-bridge it into a durable regression
    /// test, appending the written path to the rendered output. Best-effort;
    /// a write failure never fails the verify gesture.
    static func renderWithRegression(
        parsed: VerifyOutcome,
        context: VerifyResultRenderer.Context,
        entry: SemanticIndexEntry,
        packageRoot: URL,
        emitRegression: Bool
    ) -> String {
        var rendered = VerifyResultRenderer.render(parsed, context: context)
        if emitRegression, case let .defaultFails(detail) = parsed,
            let regressionPath = emitRegressionTest(
                entry: entry,
                detail: detail,
                packageRoot: packageRoot
            ) {
            let prefix = packageRoot.path + "/"
            let shown = regressionPath.path.hasPrefix(prefix)
                ? String(regressionPath.path.dropFirst(prefix.count))
                : regressionPath.path
            rendered += "\n    regression test → \(shown)"
        }
        return rendered
    }

    /// Sub-step: load the SemanticIndex + look up the suggestion by prefix.
    /// Surfaces stale-index / lookup warnings on stderr; returns the entry.
    private static func resolveEntry(
        suggestionPrefix: String,
        indexPathOverride: String?,
        packageRoot: URL
    ) throws -> SemanticIndexEntry {
        let now = ISO8601DateFormatter().string(from: Date())
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
        return lookup.entry
    }

    /// Sub-step: build the synthesized workdir and run the verifier binary.
    /// Build failures surface as `.buildFailed`; the captured run output is
    /// returned for the parser to consume.
    private static func buildAndRun(workdir: URL) throws -> VerifierSubprocess.Output {
        let buildOutput = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
        guard buildOutput.exitCode == 0 else {
            throw VerifyError.buildFailed(
                exitCode: buildOutput.exitCode,
                stderr: buildOutput.stderr
            )
        }
        return try VerifierSubprocess.runVerifierBinary(workdir: workdir)
    }
}
