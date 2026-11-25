import Foundation
import SwiftInferCore

// V1.142 lint pass — the single-suggestion verify pipeline orchestration,
// split out of `SwiftInferCommand.Verify.swift` (which had hit SwiftLint's 400-line
// file-length cap). The command shell (flags + `run()`) stays in
// `SwiftInferCommand.Verify.swift`; the pipeline steps and the v1.142 auto-bridge
// rendering live here.
extension SwiftInferCommand.Verify {

    /// Orchestration glue. Pure-ish entry point so tests can drive verify
    /// end-to-end without the AsyncParsableCommand shell. Resolves the entry,
    /// emits + builds + runs the verifier workdir, persists evidence (unless
    /// `persistEvidence` is off), and renders the outcome (appending the
    /// auto-bridge regression-test note when `emitRegression` and the run found
    /// a counterexample).
    static func runPipeline(
        suggestionPrefix: String,
        indexPathOverride: String?,
        budgetString: String,
        workingDirectory: URL,
        emitRegression: Bool = false,
        target: String? = nil,
        acceptedDedupeBody: DedupeBody? = nil,
        persistEvidence: Bool = true
    ) throws -> VerifyRun {
        let packageRoot = findPackageRoot(startingFrom: workingDirectory)
            ?? workingDirectory
        let resolved = try resolveEntry(
            suggestionPrefix: suggestionPrefix,
            indexPathOverride: indexPathOverride,
            packageRoot: packageRoot
        )
        let entry = withAcceptedRoute(resolved.entry, acceptedDedupeBody)
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
        let companions = VerifyResultParser.companionLaws(runOutput)
        // V1.142 — emit the regression test once; its path feeds both the
        // persisted evidence and the rendered output note.
        let regressionPath: URL? = {
            guard emitRegression, case let .defaultFails(detail) = parsed else { return nil }
            return emitRegressionTest(entry: entry, detail: detail, packageRoot: packageRoot)
        }()
        persistSingleRun(
            parsed: parsed,
            // The RE-SCANNED entry, not `entry`: its fingerprint is the one discover checks. An
            // accepted route (`withAcceptedRoute`) changes what ran, not what code it ran on.
            evidenceEntry: resolved.entry,
            corpusEntry: entry,
            packageRoot: packageRoot,
            regressionPath: regressionPath,
            companionLaws: companions,
            persistEvidence: persistEvidence
        )
        // The verdict and its rendering come back TOGETHER, from one `parsed`. Returning only
        // the prose is what let the speculative runner match it for "bothPass" — a word this
        // renderer never emits — and report `not-runnable` for every candidate, forever. See #116.
        let rendered = renderOutcome(
            parsed: parsed, context: stubBundle.rendererContext, entry: entry,
            packageRoot: packageRoot, regressionPath: regressionPath,
            persistEvidence: persistEvidence
        ) + VerifyResultRenderer.renderCompanions(companions)
        return VerifyRun(outcome: parsed, rendered: rendered, companionLaws: companions)
    }

    /// One verify run: the verdict, and the prose for a human.
    ///
    /// **The prose is a projection of the verdict, not a parallel encoding.** Both are
    /// computed from the same `VerifyOutcome`, so a caller can render it or switch on it and
    /// the two cannot disagree. Before this, `runPipeline` returned only the rendering and
    /// `surveyRecord` returned only the classification — one question, two encodings, and
    /// nothing relating them.
    struct VerifyRun {
        let outcome: VerifyOutcome
        let rendered: String
        /// #711 — the companion laws the stub ran beside the primary law (`CompanionLawOutcome`).
        /// Empty for every entry with none. `outcome` stays the primary law's.
        var companionLaws: [CompanionLawOutcome] = []

        /// The persisted five-way classification, via the same mapper the evidence log uses,
        /// so a consumer never has to re-derive it from prose or from disk.
        var evidenceOutcome: VerifyEvidenceOutcome {
            VerifyEvidenceRecorder.evidence(for: outcome).outcome
        }
    }

    /// #711 — `entry`, carrying the dedupe route its row had when accepted. `accept-check`
    /// re-checks what the accepted stub checks:
    /// - after an edit the body gate refuses (the insert deleted, the check negated), the accepted
    ///   count laws still run, and that edit is the regression they exist to catch;
    /// - after an edit that changes the route, the ACCEPTED route still wins. A keep-first stub
    ///   states C2 and idempotence with `==`, so a body that now returns `Array(d.values)` fails
    ///   it, and checking the re-scanned route's count form would report still-passes over a
    ///   failing test (#734's second review).
    ///
    /// The run's evidence is still stamped with the RE-SCANNED entry's fingerprint (`runPipeline`),
    /// so discover, which knows only the re-scan, can apply it.
    static func withAcceptedRoute(_ entry: SemanticIndexEntry, _ accepted: DedupeBody?) -> SemanticIndexEntry {
        guard let accepted, entry.templateName == TemplateName.idempotence.rawValue else {
            return entry
        }
        var routed = entry
        routed.dedupeBody = accepted
        return routed
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

    /// Persist one `--suggestion` run: the evidence record and, for a counterexample, the replay
    /// corpus entry. **`persistEvidence: false` skips both**, exactly what the `--all-from-index`
    /// arm skips (`persistSurveyBatch`, #129): both are outputs of the run, and a run being
    /// COMPARED against `.swiftinfer/verify-evidence.json` must not rewrite it first. The flag was
    /// parsed in both modes and read only by the survey arm, so a single-suggestion re-check
    /// silently overwrote the baseline it was meant to be compared against.
    ///
    /// The auto-bridge regression test is not gated here, as it is not in the survey arm:
    /// `--emit-regression` governs it, and the test is written before this runs.
    /// `now` is injected (defaulting to the wall clock) so a test can pin the stamp.
    static func persistSingleRun(
        parsed: VerifyOutcome,
        evidenceEntry: SemanticIndexEntry,
        corpusEntry: SemanticIndexEntry,
        packageRoot: URL,
        regressionPath: URL?,
        companionLaws: [CompanionLawOutcome] = [],
        persistEvidence: Bool = true,
        now: Date = Date()
    ) {
        guard persistEvidence else { return }
        self.persistEvidence(
            parsed: parsed,
            entry: evidenceEntry,
            packageRoot: packageRoot,
            regressionPath: regressionPath,
            companionLaws: companionLaws,
            now: now
        )
        persistCorpus(parsed: parsed, entry: corpusEntry, packageRoot: packageRoot, now: now)
    }

    /// V1.64.B — persist the outcome to `.swiftinfer/verify-evidence.json` so
    /// `discover` can annotate this suggestion later. Best-effort: a
    /// persistence failure warns on stderr but never fails the verify gesture.
    /// `now` is injected (defaulting to the wall clock) so a test can pin the
    /// stamp — SwiftProjectLint's Non-Injected Nondeterminism rule. The stamp is
    /// persisted at whole-second `.iso8601` resolution, and two records tying on
    /// it are exactly what makes the log `merge` folds non-commutative (see
    /// `MergeAlgebraPropertyTests`). Internal, not private, so a test can check what it
    /// stamps without running a subprocess (`DocumentedRangeEvidenceStampTests`).
    static func persistEvidence(
        parsed: VerifyOutcome,
        entry: SemanticIndexEntry,
        packageRoot: URL,
        regressionPath: URL?,
        companionLaws: [CompanionLawOutcome] = [],
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
                regressionTestPath: regressionPath.map { packageRelative($0, packageRoot: packageRoot) },
                // Stamp the measurement with the body it was taken against, so a later
                // `discover` can tell "this was measured on the code in front of you" from
                // "this was measured on something else". Without it the outcome outlives any
                // edit to the subject, because `identityHash` is deliberately blind to the
                // body (PRD §7.5) — road test §10.2. Folded with the bounds a
                // `documented-range` entry ran (#701); the bodies alone everywhere else.
                subjectFingerprint: entry.evidenceFingerprint,
                companionLaws: companionLaws.isEmpty ? nil : companionLaws
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
    ///
    /// With `persistEvidence: false` this run recorded nothing (`persistSingleRun`), so the corpus
    /// count on disk is not this counterexample's and `--replay-only` would not replay it: the
    /// line says so instead of printing either. The re-verify hint still holds.
    static func renderOutcome(
        parsed: VerifyOutcome,
        context: VerifyResultRenderer.Context,
        entry: SemanticIndexEntry,
        packageRoot: URL,
        regressionPath: URL?,
        persistEvidence: Bool = true
    ) -> String {
        var rendered = VerifyResultRenderer.render(parsed, context: context)
        guard case .defaultFails = parsed else { return rendered }
        if let regressionPath {
            rendered += "\n    regression test → \(packageRelative(regressionPath, packageRoot: packageRoot))"
        }
        rendered += "\n    seed: \(seedString(for: entry.identityHash))"
        let prefix = String(entry.identityHash.prefix(10))
        let reVerify = "re-verify: swift-infer verify --suggestion \(prefix)"
        guard persistEvidence else {
            rendered += "\n    corpus: not recorded (--no-persist-evidence) · \(reVerify)"
            return rendered
        }
        let corpusCount = VerifyCorpusStore.load(packageRoot: packageRoot).corpus.entries.count
        rendered += "\n    corpus: \(corpusCount) recorded"
            + " · \(reVerify)"
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
