import Foundation
import SwiftInferCore

/// V1.50.B — survey driver for `swift-infer verify --all-from-index`.
///
/// Loads the SemanticIndex (default path or via `--index-path`),
/// iterates every entry (optionally filtered by `--template`), runs
/// the verify pipeline per-entry, and emits a per-line JSON record
/// to stdout. Parallelism is bounded by `--max-parallel` via a
/// `TaskGroup`-based concurrency scheduler.
///
/// The per-entry output is the canonical Phase 2 measurement artifact.
/// Cycle-47's full-surface-outcomes.json is built by piping the stdout
/// stream through `jq -s '.' > full-surface-outcomes.json` (the
/// build-survey.sh fixture script).
extension SwiftInferCommand.Verify {

    /// Survey-mode entry point. Iterates the loaded index, runs
    /// verify per-entry in a bounded `TaskGroup`, prints one JSON
    /// record per entry. Each record line is independently valid JSON
    /// (concat them with `jq -s` to produce a top-level array).
    static func runAllFromIndex(
        indexPathOverride: String?,
        budgetString: String,
        workingDirectory: URL,
        maxParallel: Int,
        templateFilter: String?,
        corpusModuleName: String? = nil,
        emitRegression: Bool = false
    ) async throws {
        let packageRoot = findPackageRoot(startingFrom: workingDirectory)
            ?? workingDirectory
        let index = try loadIndex(
            indexPathOverride: indexPathOverride,
            packageRoot: packageRoot
        )
        let entries = filtered(entries: index.entries, templateFilter: templateFilter)
        if entries.isEmpty {
            FileHandle.standardError.write(
                Data("warning: --all-from-index found 0 entries to verify\n".utf8)
            )
            return
        }
        let parallelism = max(1, maxParallel)
        let config = SurveyConfig(
            budget: parseBudget(budgetString),
            corpusModuleName: corpusModuleName,
            emitRegression: emitRegression,
            // WS-6 Slice 2 — whole-module shape universe for recursive derivation.
            allShapes: index.typeShapes
        )
        await runParallelSurvey(
            entries: entries,
            packageRoot: packageRoot,
            parallelism: parallelism,
            config: config
        )
    }

    /// V1.142.C — per-survey constants bundled so the parallel loop's task
    /// submissions and the per-entry worker stay within the closure-/function-
    /// body-length caps.
    struct SurveyConfig {
        let budget: RoundTripStubEmitter.TrialBudget
        let corpusModuleName: String?
        let emitRegression: Bool
        /// WS-6 Slice 2 — the persisted whole-module shape universe, threaded to
        /// each per-entry `buildStubBundle` so nested custom-type carriers derive.
        var allShapes: [String: IndexedTypeShape] = [:]
    }

    static func loadIndex(
        indexPathOverride: String?,
        packageRoot: URL
    ) throws -> IndexStore.Index {
        let now = ISO8601DateFormatter().string(from: Date())
        let explicitIndexPath = indexPathOverride.map { URL(fileURLWithPath: $0) }
        // V1.42.C.5 — reindex the conventional index on demand if stale/missing.
        try reindexIfNeeded(packageRoot: packageRoot, explicitIndexPath: explicitIndexPath)
        let resolved = try VerifyHarness.resolveIndex(
            packageRoot: packageRoot,
            explicitIndexPath: explicitIndexPath,
            now: now
        )
        for warning in resolved.warnings {
            FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
        }
        return resolved.index
    }

    private static func filtered(
        entries: [SemanticIndexEntry],
        templateFilter: String?
    ) -> [SemanticIndexEntry] {
        guard let templateFilter else { return entries }
        return entries.filter { $0.templateName == templateFilter }
    }

    /// Bounded-parallel survey loop. Uses a `TaskGroup` with a
    /// semaphore-shaped wait pattern (max `parallelism` in-flight) to
    /// avoid spawning all 109 SwiftPM builds simultaneously. Output
    /// stream is `print`-serialized in submission order — JSON
    /// records emit as their pipelines complete, not in input order.
    private static func runParallelSurvey(
        entries: [SemanticIndexEntry],
        packageRoot: URL,
        parallelism: Int,
        config: SurveyConfig
    ) async {
        var collected: [SurveyRecord] = []
        await withTaskGroup(of: SurveyRecord.self) { group in
            var inFlight = 0
            var nextIndex = 0
            // Prime the pump with `parallelism` initial tasks.
            while nextIndex < entries.count, inFlight < parallelism {
                let entry = entries[nextIndex]
                nextIndex += 1
                inFlight += 1
                group.addTask {
                    surveyRecord(for: entry, packageRoot: packageRoot, config: config)
                }
            }
            // For each completion, drain + add the next.
            while let record = await group.next() {
                inFlight -= 1
                emit(record)
                collected.append(record)
                if nextIndex < entries.count {
                    let entry = entries[nextIndex]
                    nextIndex += 1
                    inFlight += 1
                    group.addTask {
                        surveyRecord(for: entry, packageRoot: packageRoot, config: config)
                    }
                }
            }
            _ = inFlight  // Defensive: silence unused-var if the compiler tracks it.
        }
        persistSurveyBatch(collected, packageRoot: packageRoot)
    }

    /// Persist a completed survey: verify-evidence (one upsert per record) and
    /// the v1.143 replay corpus (accumulate the default-fail counterexamples).
    /// One batch timestamp — the survey is one logical measurement run. Both
    /// writes are best-effort; warnings surface on stderr.
    private static func persistSurveyBatch(_ collected: [SurveyRecord], packageRoot: URL) {
        let capturedAt = Date()
        let batch = collected.map { record in
            VerifyEvidence(
                identityHash: VerifyEvidenceRecorder.normalizedIdentityHash(record.identityHash),
                template: record.templateName,
                outcome: VerifyEvidenceRecorder.evidenceOutcome(for: record.outcome),
                detail: record.outcomeDetail,
                capturedAt: capturedAt,
                swiftInferVersion: VerifyEvidenceRecorder.swiftInferVersion
            )
        }
        let corpusEntries: [VerifyCorpusEntry] = collected.compactMap { record in
            guard let counterexample = record.counterexample else { return nil }
            return VerifyCorpusEntry(
                identityHash: VerifyEvidenceRecorder.normalizedIdentityHash(record.identityHash),
                template: record.templateName,
                counterexample: counterexample,
                shrunkCounterexample: record.shrunkCounterexample,
                seed: seedString(for: record.identityHash),
                capturedAt: capturedAt,
                swiftInferVersion: VerifyEvidenceRecorder.swiftInferVersion
            )
        }
        let warnings = VerifyEvidenceRecorder.recordBatch(batch, packageRoot: packageRoot)
            + VerifyCorpusStore.recordBatch(corpusEntries, packageRoot: packageRoot)
        for warning in warnings {
            FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
        }
    }

    /// Per-entry survey worker. Runs the full verify pipeline; maps
    /// the result to a `SurveyRecord`. Catches all errors and maps
    /// them to `.measuredError` so a single failure doesn't abort
    /// the survey.
    static func surveyRecord(
        for entry: SemanticIndexEntry,
        packageRoot: URL,
        config: SurveyConfig
    ) -> SurveyRecord {
        let context = recordContext(for: entry)
        do {
            // For a curated corpus, the carriers are types in the corpus module
            // (not declared library deps), so the verifier must path-depend on
            // the corpus package + `import` it. cycle27-surface (library
            // carriers) passes nil and is unaffected.
            let extraImports = config.corpusModuleName.map { [$0] } ?? []
            let userPackage = config.corpusModuleName.map {
                VerifierWorkdir.UserPackageReference(
                    packagePath: packageRoot,
                    packageDeclaredName: $0,
                    productNames: [$0]
                )
            }
            let stubBundle = try Self.buildStubBundle(
                entry: entry,
                budget: config.budget,
                extraImports: extraImports,
                allShapes: config.allShapes
            )
            let workdir = packageRoot
                .appendingPathComponent(".swiftinfer")
                .appendingPathComponent("verify-workdir")
                .appendingPathComponent(workdirSegment(for: entry.identityHash))
            _ = try VerifierWorkdir.synthesize(
                VerifierWorkdir.Inputs(
                    workdir: workdir,
                    userPackage: userPackage,
                    stubSource: stubBundle.source
                )
            )
            let buildOutput = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
            if buildOutput.exitCode != 0 {
                return surveyRecordForBuildFailure(buildOutput: buildOutput, context: context)
            }
            let runOutput = try VerifierSubprocess.runVerifierBinary(workdir: workdir)
            let parsed = VerifyResultParser.parse(runOutput)
            emitSurveyRegression(parsed, entry: entry, packageRoot: packageRoot, enabled: config.emitRegression)
            return surveyRecord(from: parsed, context: context)
        } catch let error as VerifyError {
            // .unsupportedCarrier / .unsupportedPair / .unsupportedTemplate map
            // to architectural-coverage-pending — the architecture is
            // feature-complete for these errors' fix paths (cycle-46 framing),
            // so the residual is measurement-tooling gaps, not architectural.
            return surveyErrorRecord(context, .architecturalCoveragePending, detail(for: error))
        } catch {
            return surveyErrorRecord(context, .measuredError, "exception: \(error.localizedDescription)")
        }
    }

    /// Build a `SurveyRecord` for an error/architectural-pending outcome from
    /// the entry's context. Extracted so `surveyRecord(for:…)` stays under the
    /// function-body-length cap.
    private static func surveyErrorRecord(
        _ context: RecordContext,
        _ outcome: SurveyOutcome,
        _ detail: String?
    ) -> SurveyRecord {
        SurveyRecord(
            identityHash: context.identityHash,
            templateName: context.templateName,
            primaryFunctionName: context.primaryFunctionName,
            carrier: context.carrier,
            outcome: outcome,
            outcomeDetail: detail
        )
    }

    /// V1.89 lint pass — extracted from `surveyRecord(for:…)` so the
    /// per-entry survey worker stays under SwiftLint's 50-line cap.
    /// Classifies a non-zero `swift build` exit into either
    /// `.architecturalCoveragePending` (when the build output matches a
    /// known signature like "no such module" or "compiler crash") or
    /// `.measuredError` (everything else).
    private static func surveyRecordForBuildFailure(
        buildOutput: VerifierSubprocess.Output,
        context: RecordContext
    ) -> SurveyRecord {
        if let detail = Self.architecturalPendingDetail(
            buildStdout: buildOutput.stdout,
            buildStderr: buildOutput.stderr
        ) {
            return SurveyRecord(
                identityHash: context.identityHash,
                templateName: context.templateName,
                primaryFunctionName: context.primaryFunctionName,
                carrier: context.carrier,
                outcome: .architecturalCoveragePending,
                outcomeDetail: detail
            )
        }
        return SurveyRecord(
            identityHash: context.identityHash,
            templateName: context.templateName,
            primaryFunctionName: context.primaryFunctionName,
            carrier: context.carrier,
            outcome: .measuredError,
            outcomeDetail: "build-failed: exit=\(buildOutput.exitCode)"
        )
    }

    /// V1.142.C — survey-mode auto-bridge (opt-in via `--emit-regression`):
    /// write a regression test per counterexample. Off by default so a
    /// full-index survey doesn't flood `Tests/Generated/`.
    private static func emitSurveyRegression(
        _ parsed: VerifyOutcome,
        entry: SemanticIndexEntry,
        packageRoot: URL,
        enabled: Bool
    ) {
        guard enabled, case let .defaultFails(detail) = parsed else { return }
        _ = emitRegressionTest(entry: entry, detail: detail, packageRoot: packageRoot)
    }

    /// Translate the `VerifyOutcome` (from the parser) into a
    /// `SurveyRecord`'s outcome + detail.
    private static func surveyRecord(
        from parsed: VerifyOutcome,
        context: RecordContext
    ) -> SurveyRecord {
        let outcome: SurveyOutcome
        let detail: String?
        var counterexample: String?
        var shrunkCounterexample: String?
        switch parsed {
        case let .bothPass(defaultTrials, edgeTrials, edgeSampled):
            outcome = .measuredBothPass
            detail = "defaultTrials=\(defaultTrials) edgeTrials=\(edgeTrials) edgeSampled=\(edgeSampled)"

        case .edgeCaseAdvisory:
            outcome = .measuredEdgeCaseAdvisory
            detail = nil

        case let .defaultFails(failure):
            outcome = .measuredDefaultFails
            detail = "trial=\(failure.trial)"
            counterexample = failure.input
            shrunkCounterexample = failure.shrink?.minimal

        case let .error(reason):
            outcome = .measuredError
            detail = "parse-error: \(reason)"
        }
        return SurveyRecord(
            identityHash: context.identityHash,
            templateName: context.templateName,
            primaryFunctionName: context.primaryFunctionName,
            carrier: context.carrier,
            outcome: outcome,
            outcomeDetail: detail,
            counterexample: counterexample,
            shrunkCounterexample: shrunkCounterexample
        )
    }

    /// Map a `VerifyError` to a short human-readable detail string.
    private static func detail(for error: VerifyError) -> String {
        switch error {
        case let .unsupportedCarrier(carrier, _):
            return "unsupported-carrier: \(carrier)"

        case let .unsupportedTemplate(template, _):
            return "unsupported-template: \(template)"

        case let .unsupportedPair(forward, _):
            return "unsupported-pair: \(forward)"

        default:
            return error.description
        }
    }

    /// Per-entry context bundle to keep the worker signatures lean.
    private struct RecordContext {
        let identityHash: String
        let templateName: String
        let primaryFunctionName: String
        let carrier: String?
    }

    private static func recordContext(for entry: SemanticIndexEntry) -> RecordContext {
        RecordContext(
            identityHash: entry.identityHash,
            templateName: entry.templateName,
            primaryFunctionName: entry.primaryFunctionName,
            carrier: entry.typeName
        )
    }

    /// JSON-encode a single record and print it to stdout. One
    /// line per record — concat with `jq -s` to produce a top-level
    /// array.
    private static func emit(_ record: SurveyRecord) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(record)) ?? Data()
        if let line = String(data: data, encoding: .utf8) {
            print(line)
        }
    }
}
