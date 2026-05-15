# v1.83 Calibration Cycle 80 — Findings (V2.0.M8: effect-bearing verify + trace persistence)

Captured: 2026-05-15. swift-infer at v1.83.

## Headline

**V2.0.M8 ships in one push: three sub-cycles open the effect-bearing
reducer verify path and add failing-trace persistence under
`Tests/Generated/SwiftInferTraces/`.**

- **M8.A** — `ActionSequenceStubEmitter` accepts the two
  effect-bearing signature shapes. The returned `Effect<A>` is
  **captured into `_` and discarded** per PRD §16 #1; swift-infer
  never executes user-side Effects.
- **M8.B** — `ReducerCandidate.purity` populated by
  `ReducerPurityAnalyzer` at discovery; `.hiddenMutability` bodies
  rejected at pipeline entry; `Purity:` line in rendered outcome.
- **M8.C** — new `InteractionTraceEmitter` writes a `@Test`-shape
  regression file on `.measuredDefaultFails`. Deterministic seed
  re-use means the trace reproduces byte-stably across runs.

**Test count 2848 → 2870 (+22).** No §13 budget regression.

The verify path is now consumer-complete for v2.0's in-scope family
set. Subsequent `swift test` runs replay any failing trace as a
standard Swift Testing regression — it fails until the user repairs
the trapping reducer, then passes (or the user deletes the trace).

## M8.A — Effect-discard emit

| Signature shape | Apply-step emit |
|---|---|
| `(S, A) -> (S, Effect<A>)` | `let (newState, _) = reduce(state, action); state = newState` |
| `(inout S, A) -> Effect<A>` | `_ = reduce(&state, action)` |
| `(S, A) -> S` (unchanged) | `state = reduce(state, action)` |
| `(inout S, A) -> Void` (unchanged) | `reduce(&state, action)` |

The PRD §16 #1 invariant ("swift-infer never executes user-side
Effects") holds because the `Effect<A>` value is bound to `_` — it
is constructed (the reducer may build an `Effect.run { ... }`
closure value) but **never dispatched**. The closure body is
unrun; only the State half flows into the next iteration.

**Idempotence post-loop check** likewise picks up two new arms:
the `(S, A) -> (S, Effect<A>)` shape produces a 3-line block
(`let (once, _) = reduce(state, .case)` + `let (twice, _) =
reduce(once, .case)` + assertion); the `(inout S, A) -> Effect<A>`
shape produces a 5-line block (the copy-and-mutate dance from the
inout-Void shape, with `_ =` prefix).

**`.tca` carrier still rejected.** TCA's `Reduce { state, action
in ... }` is a closure value, not a callable on the conforming
type; calling `feature.reduce(into:action:)` requires instance-
relative init that the static-call emitter shape doesn't cover.
Separate scope from M8 — the closure-relative path is a future
addition, not a blocker for the "effect-bearing reducers work" PRD
acceptance criterion (line 731).

**Type body length housekeeping.** The Inputs + EmitError nested
types lifted to `ActionSequenceStubEmitter+Types.swift` via
extension. SwiftLint counts type body per-declaration, so extensions
shrink the parent's count — the enum now stays under the 250-line
cap as the four arms of `makeApplyStep` / `makeIdempotenceCheck`
add their effect-discard rows.

## M8.B — Purity-driven routing

`ReducerCandidate` gains a `purity: ReducerPurity` field
(`.pure` / `.effectBearing` / `.hiddenMutability`). Two discovery
paths populate it:

- **`ReducerDiscoverer.matchReducer`** — signature-scan path.
  Calls `ReducerPurityAnalyzer.analyze(FunctionDeclSyntax)` on the
  matched function decl.
- **`ReduceClosureWalker.emitCandidate`** — TCA closure path.
  Calls `ReducerPurityAnalyzer.analyze(Syntax(closure.statements))`
  on the `Reduce { state, action in ... }` body. TCA closures are
  typically `.effectBearing` (they construct `Effect.run` / `.send`
  / etc.) but signature-pure closures still qualify for the pure
  path at the routing layer.

**Routing decision matrix:**

| Purity | What the pipeline does |
|---|---|
| `.pure` | Existing M3.E path; emit via `ActionSequenceStubEmitter` |
| `.effectBearing` | Existing M3.E path; emit shape diff handled by signature, not purity |
| `.hiddenMutability` | **Reject** at pipeline entry with `VerifyInteractionError.hiddenMutability(reducer:)` |

`.pure` and `.effectBearing` flow through the same compile-once-
run-many subprocess (`VerifierWorkdir` + `VerifierSubprocess`).
The "subprocess vs in-process" distinction PRD §7 sketches is
nominal at v2.0 — both classifications currently produce the same
build-and-run-binary path. The honest distinction is "we know
this reducer is effect-shaped, so we routed it through the
effect-discard emit" rather than "we used a different process
boundary."

**`.hiddenMutability` rejection rationale.** A body that writes
to `Self.staticCounter += 1` (or `GlobalLog.entries.append(...)`)
produces non-deterministic verify outcomes because the static
state persists across action sequences — sequence #1 mutates,
sequence #2 reads the mutated value. Even if the reducer's State
type is pure-functional, the body's invariant doesn't hold under
re-execution. PRD §4.1 vetoes these with `-∞` score; M8.B carries
the same veto into the verify path, surfaced as an actionable
error instead of a confusing `.measuredDefaultFails`.

**Codable back-compat on `purity`.** Pre-M8 JSON records (none on
disk yet) default to `.pure` — the safe-to-route value. Same
pattern as M1.B's `carrierKind` back-compat.

## M8.C — Trace persistence

On `.measuredDefaultFails`, `VerifyInteractionPipeline.runPipeline`
writes a `@Test`-shape Swift source file under

```
Tests/Generated/SwiftInferTraces/<workdirSegment>/trace-replay.swift
```

where `<workdirSegment>` is the candidate's qualified name with
`.` → `_` (e.g., `Inbox.body` → `Inbox_body`). The trace file
imports `Testing` + the user module + `PropertyBased` +
`PropertyLawKit`, declares a `@Suite`-wrapped struct, and a single
`@Test func replay()` that re-runs the verifier loop with the
**same Xoshiro256** seed** as the original failing run.

**Why same-seed re-run.** Swift traps cannot be intercepted, so
the trace can't `#expect(false, ...)` inside a catch — there is
no catch. The trace instead replicates the exact path that
trapped, in the same order, with the same generator state. PRD
§16 #6's byte-identical-reproducibility guarantee makes this
work — `ActionSequenceStubEmitter.seedTuple(for:)` is a pure
function of the candidate's qualified name, so the trace file's
seed and the verifier-stub's seed are identical.

**Failure render.** Swift Testing crashes when a precondition
fires inside a `@Test` body; the test reports as a failure with
the trap stack. Until the user repairs the reducer, every
`swift test` run reproduces the failure. PRD §11's "failing
traces fail the build, drift signals only warn" distinction is
honored.

**Path layout.** Three layers of safety:
1. `Tests/Generated/` already filters out from many user
   `.gitignore` patterns ("Generated" is the conventional
   auto-write subdirectory).
2. `SwiftInferTraces/` namespace makes the origin obvious.
3. `<reducer-segment>/trace-replay.swift` overwrites idempotently
   if the same reducer fails twice — the latest failing seed wins.

**Trap-handling boundary documented in source.** The emitter's
header doc-comment explicitly notes that Swift traps cannot be
intercepted; readers of the trace file see the same explanation
in the generated `// DO NOT EDIT` block.

## What's deferred to M8 follow-ups

**Shrinking.** PRD §7.2 #3 specifies drop-prefix / drop-suffix /
halving QuickCheck shrinking to minimize the failing trace. M8.C
ships the un-shrunk trace because the M3.B verifier stub doesn't
yet print which sequence index trapped — the trace replays all N
sequences, including the (N − 1) that passed. The next M8 sub-cycle
adds:

1. A `TRACE-CURRENT-SEQ: <i>` marker the stub prints to stderr
   before each sequence iteration (unbuffered; survives trap).
2. `InteractionVerifyOutcomeParser` extraction of the last-seen
   marker on non-zero exit.
3. Re-invocation with `--pin-sequence <i>` shape to re-run a
   single sequence; drop-prefix / drop-suffix loop until further
   shrinking fails.
4. Trace file emits only the minimal failing sequence.

**Effect-bearing-reducer corpus signal.** PRD §11 acceptance
criterion line 731 requires "at least 1 effect-bearing reducer
produces `.bothPass` outcome" against the calibration corpus.
M8.A unblocks the emit path; an explicit corpus pin (probably
inside `swift-composable-architecture/Examples/`) measures the
acceptance. This is calibration work, not a code change — it
fits naturally after the v2.2.0 kit publication unblocks the
build step (`.architecturalCoveragePending` is the current
result when the kit pin can't resolve).

**`accept-check`-shaped post-acceptance flow.** v1.72 shipped
`swift-infer accept-check` as PRD §17.2's 5th metric (post-
acceptance failure rate). The analog for interaction invariants
should hook into the trace-file regression — if a previously
green trace turns red on CI, that's the v2.0 analog of v1's
"previously-accepted suggestion now fails." Trace-replay
naturally surfaces this; the question is whether to wire it
into a metrics aggregation or let CI carry the signal directly.

## What's next — M9 / M10

PRD §5.8's remaining arc:

- **M9 — InteractionInvariantBridge.** Kit-side
  `InteractionInvariant` protocol family + conformance suggestion
  when ≥ 3 Strong-tier interaction invariants fire on the same
  reducer. Cross-repo coordination — needs a SwiftPropertyLaws
  kit minor bump (`v2.3.0`) alongside the still-pending v2.2.0
  publication. The bridge is the v2.0 analog of v1's
  RefactorBridge: detect "this reducer is enough of an
  interaction-invariant-bearing thing that the user might want
  the kit protocol" and produce the conformance suggestion as
  a regular suggestion with `Score` + tier + the same two-sided
  explainability block.
- **M10 — Drift mode** for interaction invariants. Per-baseline
  warning on new Strong-tier interaction suggestions added since
  baseline. Mirrors v1's drift mechanism. Trace replays (PRD
  §11) already fail builds; drift is the non-fatal "you have
  new Strong suggestions, you should review them" signal.

Calibration cycles for M5–M7 families can also start in
parallel — each new-family M-milestone needs three cycles of
stable acceptance rate before promotion off default-`.possible`.
M5 (Cardinality), M6 (Referential Integrity), M7 (Biconditional)
are all eligible to start their calibration arcs now.

## Test count breakdown

**2848 → 2870 (+22):**

- **M8.A:** 2 `makeIdempotenceCheck` tests for effect arms (3-line
  + 5-line forms); 2 emitter-source tests flipped from
  rejection-pinning to positive emit assertions; 1 pipeline-level
  effect-tuple emit assertion (flipped from rejection-pinning).
  Net delta: +2 (flips don't add tests, only the 2 new helper-
  shape assertions do).
- **M8.B:** 3 `ReducerDiscoverer` purity-population tests (pure,
  effect-bearing, hidden-mutability); 2 `ReducerCandidate`
  purity/Codable tests (default + round-trip + missing-key
  back-compat); 1 pipeline `.hiddenMutability` rejection test;
  1 render-shows-purity test; 1 effect-tuple fixture update (body
  references `Effect.run` so purity classifies as `.effectBearing`).
  Net delta: +8.
- **M8.C:** 10 `InteractionTraceEmitter` tests (header marker,
  imports, struct/test shape, free + method + effect-tuple loop
  forms, seed-matching-stub, suite-identifier safety, path
  layout, disk round-trip); 2 render tests (trace-path shown vs
  omitted). Net delta: +12.

§13 budgets unchanged — no scan-perf surface touched.

## Artifacts

- v1.83 sources:
  - `Sources/SwiftInferCLI/ActionSequenceStubEmitter.swift`
    (M8.A: validate / makeApplyStep / makeIdempotenceCheck)
  - `Sources/SwiftInferCLI/ActionSequenceStubEmitter+Types.swift`
    (M8.A: Inputs + EmitError extension-relocation)
  - `Sources/SwiftInferCore/ReducerCandidate.swift` (M8.B: purity
    field + Codable back-compat)
  - `Sources/SwiftInferCore/ReducerDiscoverer.swift` (M8.B:
    matchReducer purity hookup)
  - `Sources/SwiftInferCore/ReduceClosureWalker.swift` (M8.B:
    TCA closure purity hookup)
  - `Sources/SwiftInferCLI/VerifyInteractionPipeline.swift`
    (M8.B + M8.C: hidden-mutability gate, trace persistence
    integration, render hook)
  - `Sources/SwiftInferCLI/InteractionTraceEmitter.swift` (M8.C:
    new file)
- Prior cycle: `docs/calibration-cycle-79-findings.md` (M7 —
  Biconditional template, PRD §5 family set complete).
- v2.0 PRD: `docs/SwiftInferProperties PRD v2.0.md`.
