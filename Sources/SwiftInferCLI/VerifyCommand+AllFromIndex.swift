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
    /// Returns the per-pick `SurveyRecord`s (with the live 5-way outcome,
    /// including `architecturalCoveragePending` — which is NOT recoverable
    /// from the persisted evidence, where it collapses to `measuredError`).
    /// `quiet` suppresses the JSON stream for callers that render their own
    /// summary (`prove-then-show`).
    @discardableResult
    static func runAllFromIndex(
        persistEvidence: Bool = true,
        scanDependencies: Bool = false,
        indexPathOverride: String?,
        budgetString: String,
        workingDirectory: URL,
        maxParallel: Int,
        templateFilter: String?,
        corpusModuleName: String? = nil,
        emitRegression: Bool = false,
        quiet: Bool = false
    ) async throws -> [SurveyRecord] {
        let packageRoot = findPackageRoot(startingFrom: workingDirectory)
            ?? workingDirectory
        let index = try loadIndex(
            indexPathOverride: indexPathOverride,
            packageRoot: packageRoot,
            scanDependencies: scanDependencies
        )
        let entries = filtered(entries: index.entries, templateFilter: templateFilter)
        if entries.isEmpty {
            FileHandle.standardError.write(
                Data("warning: --all-from-index found 0 entries to verify\n".utf8)
            )
            return []
        }
        let parallelism = max(1, maxParallel)
        // Tier 2 — resolve the library product vending the corpus module ONCE
        // per run (the dump is entry-invariant). Differs from the module when a
        // package vends it through a differently-named product; falls back to
        // the module name when unresolvable.
        let corpusProductName = corpusModuleName.map {
            PackageProductResolver.libraryProduct(exposingModule: $0, packageRoot: packageRoot) ?? $0
        }
        let config = SurveyConfig(
            budget: parseBudget(budgetString),
            corpusModuleName: corpusModuleName,
            corpusProductName: corpusProductName,
            emitRegression: emitRegression,
            // WS-6 Slice 2 — whole-module shape universe for recursive derivation.
            allShapes: index.typeShapes,
            sourceFileByTypeName: index.sourceFileByTypeName
        )
        return await runParallelSurvey(
            entries: entries,
            packageRoot: packageRoot,
            parallelism: parallelism,
            config: config,
            quiet: quiet,
            persistEvidence: persistEvidence
        )
    }

    /// V1.142.C — per-survey constants bundled so the parallel loop's task
    /// submissions and the per-entry worker stay within the closure-/function-
    /// body-length caps.
    struct SurveyConfig {
        let budget: RoundTripStubEmitter.TrialBudget
        let corpusModuleName: String?
        /// Tier 2 — the library product vending `corpusModuleName`, resolved
        /// once via `PackageProductResolver`. May differ from the module name;
        /// drives `.product(name:)` while `corpusModuleName` drives `import`.
        let corpusProductName: String?
        let emitRegression: Bool
        /// WS-6 Slice 2 — the persisted whole-module shape universe, threaded to
        /// each per-entry `buildStubBundle` so nested custom-type carriers derive.
        var allShapes: [String: IndexedTypeShape] = [:]
        /// Declaration site per type name, so each entry's wiring can import every module its
        /// carrier reaches rather than only the one the entry itself names.
        var sourceFileByTypeName: [String: String] = [:]
    }

    static func loadIndex(
        indexPathOverride: String?,
        packageRoot: URL,
        clockNow: Date = Date(),
        scanDependencies: Bool = false
    ) throws -> IndexStore.Index {
        // Injected via `now` so a test can pin it (SwiftProjectLint's
        // Non-Injected Nondeterminism rule). Only feeds `IndexStore.load`'s
        // `.empty(at:)` staleness fallback, so any stable value works.
        let now = ISO8601DateFormatter().string(from: clockNow)
        let explicitIndexPath = indexPathOverride.map { URL(fileURLWithPath: $0) }
        // V1.42.C.5 — reindex the conventional index on demand if stale/missing.
        try reindexIfNeeded(
            packageRoot: packageRoot,
            explicitIndexPath: explicitIndexPath,
            scanDependencies: scanDependencies
        )
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
    /// `quiet` suppresses the per-record JSON stream (the default `verify
    /// --all-from-index` output). `prove-then-show` sets it so it can render
    /// its own classified summary from the returned records instead.
    @discardableResult
    private static func runParallelSurvey(
        entries: [SemanticIndexEntry],
        packageRoot: URL,
        parallelism: Int,
        config: SurveyConfig,
        quiet: Bool = false,
        persistEvidence: Bool = true
    ) async -> [SurveyRecord] {
        // `parallelism` no longer schedules concurrent BUILDS — see
        // `SharedVerifierPackage`. Every stub now lives in one package, so the four
        // dependencies are resolved and compiled once instead of once per
        // suggestion, and the builds are serialized against that single `.build`.
        // Measured on `fixtures/cycle27-surface` (53 entries): 13m 30s / 24 GB at
        // parallelism 4, against **100s / 1.6 GB serial cold, 45s warm** — the
        // concurrency was paying for work that no longer exists. The flag is kept
        // because it is a documented interface and because the run phase can still
        // use it.
        _ = parallelism
        var collected: [SurveyRecord] = []
        var members: [SharedVerifierPackage.Member] = []
        for entry in entries {
            switch surveyComposition(for: entry, packageRoot: packageRoot, config: config) {
            case .terminal(let record):
                // Declines and compose errors never reach a compiler, so they are
                // settled here and never acquire a target. Same records as before;
                // only the point at which they are known has moved earlier.
                if !quiet { emit(record) }
                collected.append(record)

            case .member(let member):
                members.append(member)
            }
        }

        // Resolved from the COMPOSED members, before the quarantine filters them:
        // a survey whose every member is quarantined still ran against a corpus,
        // and dropping the provenance there would lose it from exactly the stream
        // that most needs explaining.
        let provenance = corpusProvenance(for: members)
        members = settleUnresolvableProducts(members, into: &collected, quiet: quiet)
        // #174 — before any verdict, say so if the corpus displaced a pinned
        // dependency. A reader who learns this after the stream has already
        // scrolled past has learned it too late.
        discloseSupersededDependencies(for: members)

        if !members.isEmpty {
            let sharedRoot = sharedSurveyRoot(packageRoot: packageRoot)
            do {
                _ = try SharedVerifierPackage.synthesize(members: members, at: sharedRoot)
                for member in members {
                    let record = surveyExecute(
                        member: member,
                        sharedRoot: sharedRoot,
                        packageRoot: packageRoot,
                        config: config
                    )
                    if !quiet { emit(record) }
                    collected.append(record)
                }
            } catch {
                // Synthesis is all-or-nothing: a package that could not be written
                // takes every member with it. Reported per entry rather than as one
                // line, so a survey never silently returns a short list.
                for member in members {
                    let record = surveyErrorRecord(
                        recordContext(for: member.entry), .measuredError,
                        "shared-package synthesis failed: \(error.localizedDescription)"
                    )
                    if !quiet { emit(record) }
                    collected.append(record)
                }
            }
        }
        persistSurveyBatch(
            collected,
            packageRoot: packageRoot,
            corpusProvenance: provenance,
            persistEvidence: persistEvidence
        )
        return collected
    }

    /// Where the one survey package lives. Under the same gitignored root the
    /// per-suggestion workdirs used, so `make clean-temp` already sweeps it.
    static func sharedSurveyRoot(packageRoot: URL) -> URL {
        packageRoot
            .appendingPathComponent(".swiftinfer")
            .appendingPathComponent("verify-workdir")
            .appendingPathComponent("shared-survey")
    }

    /// Either a stub that wants a target, or a record that is already settled.
    enum SurveyComposition {
        case member(SharedVerifierPackage.Member)
        case terminal(SurveyRecord)
    }

    /// Phase 1 — decide, wire, and compose the stub. **No compiler runs here.**
    ///
    /// Split out of the old single `surveyRecord` so every stub can be composed
    /// before any of them is built, which is what lets them share one package. The
    /// error mapping is unchanged and deliberately so: a structural block, an
    /// unsupported carrier and a compose exception produce the same records they
    /// always did, just sooner.
    static func surveyComposition(
        for entry: SemanticIndexEntry,
        packageRoot: URL,
        config: SurveyConfig
    ) -> SurveyComposition {
        let context = recordContext(for: entry)
        if let record = structurallyBlockedRecord(for: entry, context: context) {
            return .terminal(record)
        }
        do {
            // Wiring is one decision with three outcomes — curated corpus, derived from the
            // entry, or none — and it lives in `VerifyCommand+Wiring` beside the single-verify
            // policy it differs from.
            let wiring = Self.surveyWiring(
                for: entry,
                corpusModuleName: config.corpusModuleName,
                corpusProductName: config.corpusProductName,
                packageRoot: packageRoot,
                shapes: config.allShapes,
                sourceFiles: config.sourceFileByTypeName
            )
            let extraImports = wiring.extraImports
            let userPackage = wiring.userPackage
            let stubBundle = try Self.buildStubBundle(
                entry: entry,
                budget: config.budget,
                extraImports: extraImports,
                allShapes: config.allShapes
            )
            return .member(
                SharedVerifierPackage.Member(
                    entry: entry,
                    stubSource: stubBundle.source,
                    userPackage: userPackage,
                    // Stated rather than defaulted. The survey has always been
                    // algebraic-only — it took `VerifierWorkdir.Inputs`'s `.algebraic`
                    // default and never named it, so nothing in the old call site said
                    // so. Naming it here means a future interaction survey is a
                    // compile-time decision instead of a silent inheritance.
                    mode: .algebraic
                )
            )
        } catch let error as VerifyError {
            // A timed-out run is a *defect in what we generated*, not a coverage
            // boundary — the stub compiled and ran and simply never finished. It
            // must not be filed under architectural-coverage-pending, which reads
            // as "out of scope, nothing to fix." Conflating the two is how the
            // §9.2 codegen bugs stayed invisible; see
            // `VerifierSubprocess.defaultRunTimeout`.
            if case let .runnerCrashed(reason) = error, reason.hasPrefix("timed-out:") {
                return .terminal(surveyErrorRecord(context, .measuredError, reason))
            }
            // .unsupportedCarrier / .unsupportedPair / .unsupportedTemplate map
            // to architectural-coverage-pending — the architecture is
            // feature-complete for these errors' fix paths (cycle-46 framing),
            // so the residual is measurement-tooling gaps, not architectural.
            return .terminal(
                surveyErrorRecord(context, .architecturalCoveragePending, detail(for: error))
            )
        } catch {
            return .terminal(
                surveyErrorRecord(
                    context, .measuredError, "exception: \(error.localizedDescription)"
                )
            )
        }
    }

    /// One entry, end to end — compose, then build and run it.
    ///
    /// Kept for the single-entry callers (`--replay`, the speculative-refactor
    /// runner), which verify one suggestion and have no batch to share a package
    /// with. It goes through the SAME two phases as the survey rather than keeping a
    /// second build path alive, so a change to either phase cannot apply to the batch
    /// and miss the singletons. The package it writes holds exactly one target, which
    /// is what the per-suggestion design produced anyway.
    static func surveyRecord(
        for entry: SemanticIndexEntry,
        packageRoot: URL,
        config: SurveyConfig
    ) -> SurveyRecord {
        switch surveyComposition(for: entry, packageRoot: packageRoot, config: config) {
        case .terminal(let record):
            return record

        case .member(let member):
            // Its own root, keyed by the entry — a singleton run must not clobber a
            // survey's package, and two singleton runs against different suggestions
            // must not clobber each other. That is the isolation `VerifierWorkdir`'s
            // doc asked for, kept exactly where it is still needed.
            let root = packageRoot
                .appendingPathComponent(".swiftinfer")
                .appendingPathComponent("verify-workdir")
                .appendingPathComponent(workdirSegment(for: entry.identityHash))
            do {
                _ = try SharedVerifierPackage.synthesize(members: [member], at: root)
            } catch {
                return surveyErrorRecord(
                    recordContext(for: entry), .measuredError,
                    "package synthesis failed: \(error.localizedDescription)"
                )
            }
            return surveyExecute(
                member: member, sharedRoot: root, packageRoot: packageRoot, config: config
            )
        }
    }

    /// Phase 2 — build this member's product and run its binary.
    ///
    /// Built with `--product`, not a whole-package `swift build`: one stub that fails
    /// to compile must fail one entry. Run as its own process, so a trapping
    /// `predicate` law takes one law rather than the batch. Both properties were
    /// implicit in the per-suggestion design and are now explicit — see
    /// `SharedVerifierPackage`.
    static func surveyExecute(
        member: SharedVerifierPackage.Member,
        sharedRoot: URL,
        packageRoot: URL,
        config: SurveyConfig
    ) -> SurveyRecord {
        let context = recordContext(for: member.entry)
        do {
            let buildOutput = try VerifierSubprocess.runSwiftBuild(
                workdir: sharedRoot, product: member.targetName
            )
            if buildOutput.exitCode != 0 {
                return surveyRecordForBuildFailure(buildOutput: buildOutput, context: context)
            }
            let runOutput = try VerifierSubprocess.runVerifierBinary(
                workdir: sharedRoot, product: member.targetName
            )
            let parsed = VerifyResultParser.parse(runOutput)
            emitSurveyRegression(
                parsed, entry: member.entry, packageRoot: packageRoot,
                enabled: config.emitRegression
            )
            return surveyRecord(from: parsed, context: context)
        } catch let error as VerifyError {
            if case let .runnerCrashed(reason) = error, reason.hasPrefix("timed-out:") {
                return surveyErrorRecord(context, .measuredError, reason)
            }
            return surveyErrorRecord(context, .architecturalCoveragePending, detail(for: error))
        } catch {
            return surveyErrorRecord(
                context, .measuredError, "exception: \(error.localizedDescription)"
            )
        }
    }
}
