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

    /// V1.50.B classification — one of five outcomes per pick.
    /// Matches the v1.50 plan's five categories. Encoded as a string
    /// in the JSON output for human + machine readability.
    public enum SurveyOutcome: String, Codable, Sendable {
        case measuredBothPass = "measured-bothPass"
        case measuredEdgeCaseAdvisory = "measured-edgeCaseAdvisory"
        case measuredDefaultFails = "measured-defaultFails"
        case measuredError = "measured-error"
        case architecturalCoveragePending = "architectural-coverage-pending"
    }

    /// V1.50.B JSON output record — one per pick.
    public struct SurveyRecord: Codable, Sendable {
        public let identityHash: String
        public let templateName: String
        public let primaryFunctionName: String
        public let carrier: String?
        public let outcome: SurveyOutcome
        public let outcomeDetail: String?

        public init(
            identityHash: String,
            templateName: String,
            primaryFunctionName: String,
            carrier: String?,
            outcome: SurveyOutcome,
            outcomeDetail: String?
        ) {
            self.identityHash = identityHash
            self.templateName = templateName
            self.primaryFunctionName = primaryFunctionName
            self.carrier = carrier
            self.outcome = outcome
            self.outcomeDetail = outcomeDetail
        }
    }

    /// Survey-mode entry point. Iterates the loaded index, runs
    /// verify per-entry in a bounded `TaskGroup`, prints one JSON
    /// record per entry. Each record line is independently valid JSON
    /// (concat them with `jq -s` to produce a top-level array).
    static func runAllFromIndex(
        indexPathOverride: String?,
        budgetString: String,
        workingDirectory: URL,
        maxParallel: Int,
        templateFilter: String?
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
        let budget = parseBudget(budgetString)
        let parallelism = max(1, maxParallel)
        await runParallelSurvey(
            entries: entries,
            packageRoot: packageRoot,
            budget: budget,
            parallelism: parallelism
        )
    }

    private static func loadIndex(
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
        budget: RoundTripStubEmitter.TrialBudget,
        parallelism: Int
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
                    surveyRecord(for: entry, packageRoot: packageRoot, budget: budget)
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
                        surveyRecord(for: entry, packageRoot: packageRoot, budget: budget)
                    }
                }
            }
            _ = inFlight  // Defensive: silence unused-var if the compiler tracks it.
        }
        // V1.64.B — persist the survey batch to verify-evidence.json. The
        // stdout JSON stream is unchanged; this is an additive side file.
        // One batch timestamp: the survey is one logical measurement run.
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
        for warning in VerifyEvidenceRecorder.recordBatch(batch, packageRoot: packageRoot) {
            FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
        }
    }

    /// Per-entry survey worker. Runs the full verify pipeline; maps
    /// the result to a `SurveyRecord`. Catches all errors and maps
    /// them to `.measuredError` so a single failure doesn't abort
    /// the survey.
    private static func surveyRecord(
        for entry: SemanticIndexEntry,
        packageRoot: URL,
        budget: RoundTripStubEmitter.TrialBudget
    ) -> SurveyRecord {
        let context = recordContext(for: entry)
        do {
            let stubBundle = try Self.buildStubBundle(entry: entry, budget: budget)
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
            let buildOutput = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
            if buildOutput.exitCode != 0 {
                return surveyRecordForBuildFailure(buildOutput: buildOutput, context: context)
            }
            let runOutput = try VerifierSubprocess.runVerifierBinary(workdir: workdir)
            let parsed = VerifyResultParser.parse(runOutput)
            return surveyRecord(from: parsed, context: context)
        } catch let error as VerifyError {
            // .unsupportedCarrier, .unsupportedPair, .unsupportedTemplate
            // all map to architectural-coverage-pending — the architecture
            // is feature-complete for these errors' fix paths
            // (cycle-46 framing), so the residual is measurement-tooling
            // gaps, not architectural gaps.
            return SurveyRecord(
                identityHash: context.identityHash,
                templateName: context.templateName,
                primaryFunctionName: context.primaryFunctionName,
                carrier: context.carrier,
                outcome: .architecturalCoveragePending,
                outcomeDetail: detail(for: error)
            )
        } catch {
            return SurveyRecord(
                identityHash: context.identityHash,
                templateName: context.templateName,
                primaryFunctionName: context.primaryFunctionName,
                carrier: context.carrier,
                outcome: .measuredError,
                outcomeDetail: "exception: \(error.localizedDescription)"
            )
        }
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

    /// Translate the `VerifyOutcome` (from the parser) into a
    /// `SurveyRecord`'s outcome + detail.
    private static func surveyRecord(
        from parsed: VerifyOutcome,
        context: RecordContext
    ) -> SurveyRecord {
        let outcome: SurveyOutcome
        let detail: String?
        switch parsed {
        case let .bothPass(defaultTrials, edgeTrials, edgeSampled):
            outcome = .measuredBothPass
            detail = "defaultTrials=\(defaultTrials) edgeTrials=\(edgeTrials) edgeSampled=\(edgeSampled)"
        case .edgeCaseAdvisory:
            outcome = .measuredEdgeCaseAdvisory
            detail = nil
        case let .defaultFails(trial, _, _, _):
            outcome = .measuredDefaultFails
            detail = "trial=\(trial)"
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
            outcomeDetail: detail
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
