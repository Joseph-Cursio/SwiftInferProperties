import Foundation
import SwiftInferCore
import SwiftInferTestLifter

// The pure resolve-and-emit leg of the interaction verify pipeline, plus its
// TestStore Trace Mining (Slice 2) core. Extracted from
// VerifyInteractionPipeline.swift for the SwiftLint file_length /
// type_body_length caps. No behavior lives here that the main file's
// `runPipeline` / `runWithInvariant` don't drive.

extension VerifyInteractionPipeline {

    /// Result of `resolveEmitAndSeed`: the resolved reducer, the emitted
    /// verifier source, and how many developer-authored `TestStore` orderings
    /// were mined into it (for the replay-then-extend verdict disclosure).
    struct SeededEmission {
        let candidate: ReducerCandidate
        let stubSource: String
        let seedTraceCount: Int
    }

    /// V2.0 M3.C — pure leg: discover candidates, apply pin filter, emit the
    /// stub source. No subprocess; no disk writes outside the source-tree
    /// walk. Returns the resolved candidate plus the M3.B-emitted main.swift
    /// so callers route into the build/run leg (M3.E) or render a dry-run
    /// stub-only output. Drops the Slice-2 seed count for its stable
    /// two-element contract (many tests destructure it).
    public static func resolveAndEmit(
        target: String,
        pinRaw: String? = nil,
        sequenceCount: Int = ActionSequenceStubEmitter.defaultSequenceCount,
        userModuleName: String? = nil,
        invariant: InteractionInvariantSuggestion? = nil,
        workingDirectory: URL
    ) throws -> (candidate: ReducerCandidate, stubSource: String) {
        let seeded = try resolveEmitAndSeed(
            target: target,
            pinRaw: pinRaw,
            sequenceCount: sequenceCount,
            userModuleName: userModuleName,
            invariant: invariant,
            workingDirectory: workingDirectory
        )
        return (seeded.candidate, seeded.stubSource)
    }

    /// TestStore Trace Mining options threaded from the CLI (Slice 3d/3e).
    public struct TraceMiningOptions: Sendable {
        public var prefixBias: Bool
        public var markov: Bool

        public static let off = Self()

        public init(prefixBias: Bool = false, markov: Bool = false) {
            self.prefixBias = prefixBias
            self.markov = markov
        }
    }

    /// Slice-2-aware core of `resolveAndEmit`: additionally mines the
    /// project's `TestStore` tests, selects the payload-free orderings for the
    /// resolved candidate, threads them into the stub, and reports the count
    /// so callers can disclose it in the verdict (replay-then-extend
    /// explainability). Mining is best-effort — a missing `Tests/` dir or a
    /// non-`.tca` candidate simply yields no seed traces (byte-identical
    /// stub), so this never changes behavior for the un-mined path.
    static func resolveEmitAndSeed(
        target: String,
        pinRaw: String? = nil,
        sequenceCount: Int = ActionSequenceStubEmitter.defaultSequenceCount,
        userModuleName: String? = nil,
        invariant: InteractionInvariantSuggestion? = nil,
        traceMining: TraceMiningOptions = .off,
        workingDirectory: URL
    ) throws -> SeededEmission {
        let matched = try resolveCandidate(
            target: target,
            pinRaw: pinRaw,
            workingDirectory: workingDirectory
        )
        let resolvedModuleName = userModuleName ?? target
        // TestStore Trace Mining — mine the project's tests, resolve the Action
        // alphabet, and select replayable orderings for this candidate.
        // Best-effort: no `Tests/` dir / no matching reducer → empty →
        // byte-identical un-mined stub.
        let sourcesDir = workingDirectory
            .appendingPathComponent("Sources")
            .appendingPathComponent(target)
        let minedTraces = (try? TestStoreTraceExtractor.extract(
            fromTestsDirectory: workingDirectory.appendingPathComponent("Tests")
        )) ?? []
        let alphabet = ActionAlphabetScanner.scan(
            directory: sourcesDir,
            actionTypeName: matched.actionTypeName
        )
        let seedTraces = MinedTraceSelector.select(
            from: minedTraces,
            candidate: matched,
            alphabet: alphabet,
            includeMarkov: traceMining.markov
        )
        let inputs = ActionSequenceStubEmitter.Inputs(
            candidate: matched,
            userModuleName: resolvedModuleName,
            sequenceCount: sequenceCount,
            invariant: invariant,
            seedTraces: seedTraces,
            prefixBias: traceMining.prefixBias
        )
        let stubSource: String
        do {
            stubSource = try ActionSequenceStubEmitter.emit(inputs)
        } catch let error as ActionSequenceStubEmitter.EmitError {
            throw VerifyInteractionError.unsupported(reason: error.description)
        }
        return SeededEmission(
            candidate: matched,
            stubSource: stubSource,
            seedTraceCount: seedTraces.count
        )
    }

    /// Discover → dedup composed bodies → pin-resolve → enrich composition
    /// action cases → reject hidden-mutability / bare-async reducers. The
    /// candidate-resolution half of `resolveEmitAndSeed`, split out to keep
    /// that function under the body-length cap.
    private static func resolveCandidate(
        target: String,
        pinRaw: String?,
        workingDirectory: URL
    ) throws -> ReducerCandidate {
        let directory = workingDirectory
            .appendingPathComponent("Sources")
            .appendingPathComponent(target)
        let candidates = try ReducerDiscoverer.discover(directory: directory)
        // Cycle 133 — collapse composed-body duplicates before pin resolution.
        // A composed `var body` (multiple `Reduce {}` closures, or `Reduce` +
        // `Scope`/`CombineReducers`) emits one candidate per closure (PRD
        // §6.3), all with the same qualifiedName / State / Action — which
        // `resolveCandidate` would otherwise reject as `ambiguousPin`. Mirrors
        // the discover path's dedup; the deduped candidate verifies the whole
        // composed body via `T().reduce`.
        let deduped = SwiftInferCommand.DiscoverInteraction.dedupedByStateAndAction(candidates)
        let resolved = try resolveCandidate(candidates: deduped, pinRaw: pinRaw)
        // Item 2 slices 3/4 — enrich composition-action cases so the relaxed
        // generator can construct them (the enriched candidate is used for emit
        // AND returned, so the evidence coverage fold sees the same cases):
        // slice 3 resolves `IdentifiedActionOf<Child>` against the full
        // candidate set; slice 4 resolves `binding(BindingAction<State>)`
        // against the candidate's own `@ObservableState` fields.
        let matched = BindingActionResolver.resolve(
            IdentifiedActionResolver.resolve(resolved, among: deduped)
        )
        // M8.B — hidden-mutability bodies write to static / global vars;
        // running N action sequences against such a reducer produces
        // meaningless outcomes (state persists across runs). Reject cleanly so
        // the caller surfaces an actionable error instead of a confusing
        // `.measuredDefaultFails`.
        if matched.purity == .hiddenMutability {
            throw VerifyInteractionError.hiddenMutability(reducer: matched.qualifiedName)
        }
        // Workplan Phase 4, reducer-path slice — async reducers are admitted
        // under the clock-determinism claim (`@ClockDeterministic` /
        // `/// @lint.determinism clock_deterministic`): the emitter awaits the
        // reducer from an async `main()`. Bare async stays rejected —
        // un-annotated async would make seeded sequence replays
        // nondeterministic (same conjunction posture as the ViewModel action
        // surface and the generic-laws determinism template).
        if matched.isAsync, matched.isClockDeterministic == false {
            throw VerifyInteractionError.asyncReducer(reducer: matched.qualifiedName)
        }
        return matched
    }
}
