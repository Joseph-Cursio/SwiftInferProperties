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
        try await runParallelSurvey(
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
    ) async throws {
        var collected: [SurveyRecord] = []
        await withTaskGroup(of: SurveyRecord.self) { group in
            var inFlight = 0
            var nextIndex = 0
            // Prime the pump with `parallelism` initial tasks.
            while nextIndex < entries.count && inFlight < parallelism {
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
            guard buildOutput.exitCode == 0 else {
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

    /// V1.56.A — reclassify build failures whose cause is a known
    /// architectural-coverage-pending category, returning a short
    /// detail string suitable for the SurveyRecord. Returns `nil` when
    /// the build failure doesn't match any known category — caller
    /// keeps the v1.52 `.measured-error` classification.
    ///
    /// **Currently recognized**:
    ///   - `is inaccessible due to '<access-level>'` → `"internal-api-not-accessible"`.
    ///     Cycle-52 surfaced 2 `Complex.rescaledDivide(_:_:)` picks
    ///     declared `internal` in swift-numerics. Accessibility is a
    ///     measurement-tooling gap (fix: skip non-public symbols at
    ///     indexer time, or `@testable import` in the workdir), not a
    ///     verifier-architecture gap.
    ///   - `instance member ... cannot be used on type` →
    ///     `"instance-method-shape-not-supported"`. V1.59.A surfaced
    ///     23 OS picks that compile-fail because the resolver builds
    ///     `OrderedSet.sort(value)` (static call) but `sort()` is an
    ///     instance method. Mutating-instance-method emission is
    ///     v1.60+ scope; the picks remain architecturally pending
    ///     until then.
    ///
    /// **Why both streams**: `swift build` formats compiler diagnostics
    /// to stdout (parent-process-readable) and emits SwiftPM-level
    /// errors to stderr. Cycle-53 measurement (`docs/calibration-
    /// cycle-53-findings.md`) confirmed the "inaccessible due to"
    /// message lands on stdout; checking both makes the pattern robust
    /// against SwiftPM future-version changes.
    ///
    /// **Extension point**: v1.60+ may add more patterns (e.g. for
    /// `@_spi` symbols, ambiguous overloads, etc.) as cycle-N evidence
    /// motivates.
    static func architecturalPendingDetail(
        buildStdout: String,
        buildStderr: String
    ) -> String? {
        if buildStdout.contains("is inaccessible due to '")
            || buildStderr.contains("is inaccessible due to '") {
            return "internal-api-not-accessible"
        }
        // V1.59.A — recognize instance-method-on-type errors. Three
        // related Swift compiler diagnostics for the same root cause
        // (synthesized stub calls `<Type>.<method>(value)` static shape
        // but `<method>` is an instance method). Mutating-instance-
        // method emission is v1.60+ scope.
        //
        // **(a)** `instance member ... cannot be used on type` — the
        //         canonical diagnostic.
        // **(b)** `no exact matches in call to instance method` — Swift
        //         emits this when there's an instance method matching
        //         the name but no static overload.
        // **(c)** `compile command failed due to signal` (typically
        //         signal 6 = SIGABRT) — swift-frontend CRASH on the
        //         static-call-of-instance-mutating-method shape. Empirical
        //         in cycle-56 on OS picks like `_ensureUnique()`,
        //         `_isUnique()`, `_regenerateHashTable()`. The compiler
        //         bails before emitting a structured diagnostic, but
        //         the underlying cause is the same instance-method-shape
        //         gap. Match conservatively — only when the
        //         `emit-module` or `compile command` strings appear
        //         alongside `signal`, not on arbitrary signal mentions.
        let instanceMemberOnType = "cannot be used on type"
        let noExactMatchesInstance = "no exact matches in call to instance method"
        // V1.63.A — `generic parameter '<X>' could not be inferred` is
        // the diagnostic Swift produces when a static-call-shape on a
        // nested generic type can't resolve type arguments (e.g.
        // `OrderedDictionary.Elements.distance(value, ...)` on OD's
        // `.elements` view — Swift can't infer Key/Value without an
        // instance-call shape). Same architectural category as the
        // other instance-method-shape errors.
        let cannotInferGenericParam = "could not be inferred"
        let compileCrashOnSignal =
            (buildStdout.contains("compile command failed due to signal")
                || buildStdout.contains("emit-module command failed due to signal"))
        let stderrCrashOnSignal =
            (buildStderr.contains("compile command failed due to signal")
                || buildStderr.contains("emit-module command failed due to signal"))
        let stdoutInstanceMember =
            (buildStdout.contains("instance member") && buildStdout.contains(instanceMemberOnType))
            || buildStdout.contains(noExactMatchesInstance)
            || (buildStdout.contains("generic parameter") && buildStdout.contains(cannotInferGenericParam))
            || compileCrashOnSignal
        let stderrInstanceMember =
            (buildStderr.contains("instance member") && buildStderr.contains(instanceMemberOnType))
            || buildStderr.contains(noExactMatchesInstance)
            || (buildStderr.contains("generic parameter") && buildStderr.contains(cannotInferGenericParam))
            || stderrCrashOnSignal
        if stdoutInstanceMember || stderrInstanceMember {
            return "instance-method-shape-not-supported"
        }
        // V1.59.A — monotonicity picks on non-Comparable carriers
        // (e.g. `OrderedSet<Int>` doesn't conform to `Comparable`) hit
        // `global function 'min' requires that '<Carrier>' conform to
        // 'Comparable'` — the monotonicity stub uses `min`/`max` to
        // order the two trial values. v1.61+ may add a Comparable-
        // aware monotonicity composer or a different value-ordering
        // strategy for non-Comparable carriers.
        let requiresConformance = "requires that"
        let conformTo = "conform to"
        let stdoutConformance =
            buildStdout.contains(requiresConformance) && buildStdout.contains(conformTo)
        let stderrConformance =
            buildStderr.contains(requiresConformance) && buildStderr.contains(conformTo)
        if stdoutConformance || stderrConformance {
            return "carrier-missing-required-conformance"
        }
        return nil
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
