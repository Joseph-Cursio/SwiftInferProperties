import Foundation
import SwiftInferCore
import SwiftInferTestLifter

/// V2.0 M3.C → M3.E — orchestration glue for the in-process
/// interaction verify path. Threads M1's reducer discovery → M1.C's
/// pin resolution → M3.B's stub emission → M3.E's workdir-synthesis
/// → build + run + outcome parsing → rendered five-category outcome.
///
/// **Two entries:**
///   - `resolveAndEmit(target:pinRaw:...:)` — pure, no subprocess.
///     Discovers reducers, applies the pin filter, emits the verifier
///     stub source. Used by tests; consumed by `runPipeline` as the
///     pre-execution leg.
///   - `runPipeline(target:pinRaw:...:)` — the full path. Wraps
///     `resolveAndEmit` + `executeAndParse` + outcome render. The
///     CLI subcommand (M3.D) calls this.
public enum VerifyInteractionPipeline {

    // `resolveAndEmit` (public pure leg) + `resolveEmitAndSeed` (its
    // Slice-2-aware core, which mines the project's `TestStore` tests and
    // threads the payload-free orderings into the stub) + the `SeededEmission`
    // result live in VerifyInteractionPipeline+Resolve.swift (extracted for
    // the SwiftLint file_length / type_body_length caps).

    /// V2.0 M3.E.4 — full path: resolveAndEmit → synthesize a
    /// workdir under `<packageRoot>/.swiftinfer/verify-interaction-workdir/`
    /// → `swift build` → run the verifier binary → parse outcome
    /// via `InteractionVerifyOutcomeParser` → render in the v1.42
    /// five-category format.
    ///
    /// A workdir `swift build` that fails to resolve or compile surfaces
    /// as `.architecturalCoveragePending` rather than a pass/fail. The
    /// historical "kit-tag-publication gap" cause (SwiftPropertyLaws v2.2.0
    /// not yet on remote; `docs/calibration-cycle-73-findings.md`) is
    /// resolved — the package pins SwiftPropertyLaws 3.3.0+ — so this now
    /// means a genuine coverage gap (unsupported shape/carrier, non-
    /// Equatable State), not a missing tag.
    public static func runPipeline(
        target: String,
        pinRaw: String? = nil,
        sequenceCount: Int = ActionSequenceStubEmitter.defaultSequenceCount,
        userModuleName: String? = nil,
        traceMining: TraceMiningOptions = .off,
        workingDirectory: URL
    ) throws -> String {
        let seeded = try resolveEmitAndSeed(
            target: target,
            pinRaw: pinRaw,
            sequenceCount: sequenceCount,
            userModuleName: userModuleName,
            traceMining: traceMining,
            workingDirectory: workingDirectory
        )
        let candidate = seeded.candidate
        let stubSource = seeded.stubSource
        let resolvedModuleName = userModuleName ?? target
        let result = try executeAndParse(
            candidate: candidate,
            stubSource: stubSource,
            userModuleName: resolvedModuleName,
            workingDirectory: workingDirectory,
            corpusSourceDirectory: corpusSourceDirectory(target: target, workingDirectory: workingDirectory),
            seedTraceCount: seeded.seedTraceCount
        )
        // V2.0 M8.C — on `.measuredDefaultFails`, persist a @Test-shape
        // regression file under `Tests/Generated/SwiftInferTraces/`.
        // The trace replays the same verifier loop with the same
        // deterministic seed; CI subsequently runs it as a standard
        // regression test until the user fixes the trapping reducer.
        var tracePath: URL?
        if result.outcome == .measuredDefaultFails {
            let packageRoot = findPackageRoot(startingFrom: workingDirectory) ?? workingDirectory
            // M8.D.3 + M8.D.4 — two-phase binary-search shrink over
            // (prefixLength, suffixStart). Each phase is O(log N)
            // re-invocations; total O(log²N) ≈ 25 for upperBound=16.
            var shrinkResult: InteractionShrinker.ShrinkResult?
            if let failingIndex = result.failingSequenceIndex {
                let workdir = packageRoot
                    .appendingPathComponent(".swiftinfer")
                    .appendingPathComponent("verify-interaction-workdir")
                    .appendingPathComponent(workdirSegment(for: candidate))
                shrinkResult = InteractionShrinker.shrink(
                    failingSequenceIndex: failingIndex,
                    upperBound: ActionSequenceStubEmitter.defaultLengthUpperBound,
                    runner: InteractionShrinker.liveRunner(workdir: workdir)
                )
            }
            let traceInputs = InteractionTraceEmitter.Inputs(
                candidate: candidate,
                userModuleName: resolvedModuleName,
                sequenceCount: sequenceCount,
                failingSequenceIndex: result.failingSequenceIndex,
                minimumFailingPrefixLength: shrinkResult?.prefixLength,
                minimumFailingSuffixStart: shrinkResult?.suffixStart
            )
            tracePath = try? InteractionTraceEmitter.persist(
                inputs: traceInputs,
                packageRoot: packageRoot
            )
        }
        return renderOutcome(candidate: candidate, result: result, tracePath: tracePath)
    }

    /// V2.0 accept-check follow-up — invariant-bearing entry that
    /// returns the parsed `InteractionVerifyOutcomeParser.Result`
    /// directly (instead of a rendered string). Used by
    /// `accept-check-interaction` so it can classify outcomes into
    /// `InteractionPostAcceptanceOutcomeKind` without parsing
    /// rendered text. The invariant's `reducerQualifiedName` doubles
    /// as the implicit `--reducer` pin so the right candidate is
    /// resolved when the target has multiple reducers.
    /// Cycle 120: `persistEvidence: false` suppresses the per-call upsert
    /// so the survey can batch-record once (race-free under M3 parallelism).
    public static func runWithInvariant(
        target: String,
        invariant: InteractionInvariantSuggestion,
        sequenceCount: Int = ActionSequenceStubEmitter.defaultSequenceCount,
        userModuleName: String? = nil,
        persistEvidence: Bool = true,
        workingDirectory: URL
    ) throws -> InteractionVerifyOutcomeParser.Result {
        let seeded = try resolveEmitAndSeed(
            target: target,
            pinRaw: invariant.reducerQualifiedName,
            sequenceCount: sequenceCount,
            userModuleName: userModuleName,
            invariant: invariant,
            workingDirectory: workingDirectory
        )
        let candidate = seeded.candidate
        let stubSource = seeded.stubSource
        // Cycle 139 — refint Identifiable gate: skip the build (disclosed
        // architectural-coverage-pending) when `$0.id` provably can't compile.
        if let skip = applyRefintIdentifiabilityGate(
            invariant: invariant, candidate: candidate, target: target,
            persistEvidence: persistEvidence, workingDirectory: workingDirectory
        ) {
            return skip
        }
        // Payload-bearing idempotence witness with a non-constructible payload:
        // the emitter's bare-`.select` fallback can't compile, so skip the
        // build (disclosed coverage-pending) instead of wasting it.
        if let skip = applyIdempotenceWitnessConstructibilityGate(
            invariant: invariant, candidate: candidate, target: target,
            persistEvidence: persistEvidence, workingDirectory: workingDirectory
        ) {
            return skip
        }
        let result = try executeAndParse(
            candidate: candidate,
            stubSource: stubSource,
            userModuleName: userModuleName ?? target,
            workingDirectory: workingDirectory,
            corpusSourceDirectory: corpusSourceDirectory(target: target, workingDirectory: workingDirectory),
            seedTraceCount: seeded.seedTraceCount
            // Cycle 120 m4 — reducer-keyed workdir (identity omitted). The
            // survey parallelizes *across* reducers but runs one reducer's
            // sibling identities serially in this shared warm workdir, so
            // the 2nd+ identity rebuilds incrementally instead of cold.
            // (`workdirSegment`'s `identity:` per-invariant form is retained
            // for a potential intra-reducer fan-out but unused on this path.)
        )
        // Cycle 111 — persist the measured outcome to
        // `.swiftinfer/verify-evidence.json`, keyed by the invariant's
        // identity, so `discover-interaction` can join evidence back onto
        // the suggestion (the M9 outcome→evidence→tier promotion path).
        // Mirrors `VerifyCommand.runPipeline`'s algebraic recording.
        // Only reachable from the invariant-bearing entry: the bare
        // `runPipeline` (no invariant) has no identity hash to key on.
        // Best-effort — a persistence failure warns, never fails verify.
        if persistEvidence {
            recordEvidence(invariant: invariant, result: result, workingDirectory: workingDirectory)
        }
        return result
    }

    // MARK: - Pin resolution

    /// V2.0 M3.C — pin-resolution sub-step. Pulled to a static so
    /// tests can drive it without the directory walk. Errors map
    /// 1:1 with the user-facing failure modes.
    static func resolveCandidate(
        candidates: [ReducerCandidate],
        pinRaw: String?
    ) throws -> ReducerCandidate {
        if let pinRaw {
            // Cycle 117 — prefer an exact qualified-name match before the
            // lenient `(functionName, optional typeName)` pin match. A
            // free-function reducer's qualifiedName is its bare function
            // name (e.g. `reduce`), which the lenient match also matches
            // against every same-named *method* — so a free `reduce`
            // alongside `Foo.reduce` is otherwise unresolvable (the
            // cycle-116 finding the `--all` survey hit). An exact
            // qualifiedName hit disambiguates the free function (and
            // resolves any fully-qualified pin directly). Falling through
            // to the lenient match preserves the bare-name convenience
            // (`--reducer body` → `Inbox.body`) and the correct
            // ambiguous-pin error for same-named methods, since their
            // qualifiedNames carry the type prefix and so never exact-match
            // a bare pin.
            let exact = candidates.filter { $0.qualifiedName == pinRaw }
            if exact.count == 1 {
                return exact[0]
            }
            let pin = try ReducerPin.parse(pinRaw)
            let matched = candidates.filter { pin.matches($0) }
            switch matched.count {
            case 0:
                throw VerifyInteractionError.noMatchingReducer(pin: pinRaw)

            case 1:
                return matched[0]

            default:
                throw VerifyInteractionError.ambiguousPin(
                    pin: pinRaw,
                    matches: matched.map(\.qualifiedName)
                )
            }
        }
        switch candidates.count {
        case 0:
            throw VerifyInteractionError.noReducersDetected

        case 1:
            return candidates[0]

        default:
            throw VerifyInteractionError.requiresPin(
                candidates: candidates.map(\.qualifiedName)
            )
        }
    }

    // MARK: - Build + run + parse (M3.E.4)

    /// V2.0 M3.E.4 — synthesize the workdir, run `swift build`, run
    /// the resulting binary, parse the outcome. Returns the
    /// classified result; the caller renders it.
    /// Cycle 120: `identity` keys the workdir per-invariant (see
    /// `workdirSegment`); `nil` keeps the reducer-only segment.
    static func executeAndParse(
        candidate: ReducerCandidate,
        stubSource: String,
        userModuleName: String,
        workingDirectory: URL,
        identity: String? = nil,
        corpusSourceDirectory: URL? = nil,
        seedTraceCount: Int = 0
    ) throws -> InteractionVerifyOutcomeParser.Result {
        let packageRoot = findPackageRoot(startingFrom: workingDirectory) ?? workingDirectory
        let (workdir, workdirInputs) = makeWorkdirInputs(WorkdirRequest(
            candidate: candidate,
            stubSource: stubSource,
            userModuleName: userModuleName,
            packageRoot: packageRoot,
            identity: identity,
            corpusSourceDirectory: corpusSourceDirectory
        ))
        // Cycle 129 — serialize synthesize → build → run per workdir. The
        // shared TCA workdir thus warm-reuses serially (one cold build, then
        // stub-only incrementals) with no clobbering; distinct non-TCA
        // workdirs hold distinct locks and still run in parallel.
        let lock = workdirLock(forPath: workdir.path)
        lock.lock()
        defer { lock.unlock() }
        _ = try VerifierWorkdir.synthesize(workdirInputs)

        let buildOutput = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
        if buildOutput.exitCode != 0 {
            return InteractionVerifyOutcomeParser.parseBuildFailure(
                buildExitCode: buildOutput.exitCode,
                stderr: buildOutput.stderr
            )
        }
        let runOutput = try VerifierSubprocess.runVerifierBinary(workdir: workdir)
        let parsed = InteractionVerifyOutcomeParser.parseRunOutput(
            binaryExitCode: runOutput.exitCode,
            stdout: runOutput.stdout,
            stderr: runOutput.stderr
        )
        let folded = foldPartialExplorationDisclosure(parsed, candidate: candidate)
        return foldSeedTraceDisclosure(folded, seedTraceCount: seedTraceCount)
    }

    // `findPackageRoot` + `workdirSegment` live in
    // VerifyInteractionPipeline+Workdir.swift (cycle 120 split — keeps
    // this file under SwiftLint's file_length cap).

    // MARK: - Outcome render

    /// V2.0 M3.E.4 — five-category outcome rendering. Mirrors
    /// `VerifyResultRenderer.render` shape but for interaction-
    /// invariant outcomes. (Historical note: this renders the *live*
    /// verify outcome only; the M9 evidence→tier join it once deferred
    /// has since shipped — `recordEvidence` persists to
    /// `verify-evidence.json` (cycle 111), `InteractionVerifyEvidenceScoring`
    /// folds it back at `discover-interaction` (cycle 112), and
    /// `metrics-interaction` reports it.)
    static func renderOutcome(
        candidate: ReducerCandidate,
        result: InteractionVerifyOutcomeParser.Result,
        tracePath: URL? = nil
    ) -> String {
        let header = [
            "swift-infer verify-interaction — V2.0 M3.E + M8.B + M8.C:",
            "  Reducer: \(candidate.qualifiedName)",
            "  Carrier: \(candidate.carrierKind.rawValue)",
            "  Signature: \(candidate.signatureShape.rawValue)",
            "  Purity: \(candidate.purity.rawValue)",
            "  State: \(candidate.stateTypeName)",
            "  Action: \(candidate.actionTypeName)",
            "",
            "  Outcome: \(result.outcome.rawValue)"
        ]
        var lines = header
        if let totalRuns = result.totalRuns, let clean = result.cleanRuns {
            lines.append("  Total runs: \(totalRuns)")
            lines.append("  Clean runs: \(clean)")
        }
        if let detail = result.detail {
            lines.append("  Detail: \(detail)")
        }
        if let tracePath {
            lines.append("  Trace: \(tracePath.path)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

// `VerifyInteractionError` is declared in `VerifyInteractionError.swift`
// (extracted for the `file_length` cap).
