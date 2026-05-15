# v1.84 Calibration Cycle 81 — Findings (V2.0.M8.D: minimal-trace shrinking)

Captured: 2026-05-15. swift-infer at v1.84.

## Headline

**V2.0.M8.D ships in one push: failing traces are now minimal
regression artifacts.** Three sub-cycles close PRD §7.2 #3's
drop-suffix / halving class of shrinking:

- **M8.D.1** — verifier stub emits a per-iteration stderr marker;
  parser recovers the failing sequence index on non-zero exit;
  trace switches to burn-then-replay-one shape.
- **M8.D.2** — stub reads pin-sequence + prefix-length env vars
  for single-sequence replay; `VerifierSubprocess.runVerifierBinary`
  threads extra environment through.
- **M8.D.3** — new `InteractionShrinker` runs O(log N) binary
  search over the prefix-length axis to find the minimal
  trap-inducing action list; trace replays only those actions.

**Test count 2870 → 2897 (+27).** No §13 budget regression.

A trap that originally required burning 41 sequences + a 16-action
sequence now collapses to: burn 41 sequences, run a `k`-action
prefix where `k` is the smallest prefix that still traps. PRD §16 #6's
byte-stable seed guarantee makes the shrink result deterministic —
the same trapping reducer always produces the same minimal trace.

## M8.D.1 — Failing-sequence-index recovery

The verifier stub now writes `TRACE-CURRENT-SEQ: <i>` to stderr
before each generator step:

```swift
FileHandle.standardError.write(
    Data("TRACE-CURRENT-SEQ: \(sequenceIndex)\n".utf8)
)
```

**Why stderr.** Swift's `print` to stdout is line-buffered, so a
trap that fires mid-iteration may lose buffered content. stderr on
macOS is unbuffered (or at least flushed on trap), so the last-
seen marker survives. Writing via `FileHandle` directly bypasses
any Swift-side buffering layer.

`InteractionVerifyOutcomeParser.parseRunOutput` now accepts a
stderr parameter and scans for the last `TRACE-CURRENT-SEQ:`
prefix-bearing line on non-zero exit. The integer after the prefix
becomes `Result.failingSequenceIndex`.

`InteractionTraceEmitter.Inputs.failingSequenceIndex` threads
through to the trace's replay body:
- **nil** (M8.C posture): for _ in 0..<N { ... } — replay all
  sequences, slow but correct
- **0**: skip the burn loop entirely; immediately draw the
  failing sequence
- **i > 0**: `for _ in 0..<i { _ = generator.run(using: &rng) }`
  to advance Xoshiro256** to the exact state, then draw + execute
  the (i+1)th sequence

## M8.D.2 — Pin-sequence env-var replay

Two env vars the stub reads at start-up:

| Env var | Type | Meaning |
|---|---|---|
| `SWIFT_INFER_PIN_SEQUENCE` | Int | Execute only this sequence index; skip all others (still drawing to advance rng) |
| `SWIFT_INFER_PIN_PREFIX_LENGTH` | Int | Truncate the pinned sequence's action list to the first `k` actions |

The stub's per-iteration block now looks like:

```swift
let rawActions = generator.run(using: &rng)     // always draw
if let pin = pinSequence, sequenceIndex != pin { continue }
let actions = pinPrefix.map { Array(rawActions.prefix($0)) } ?? rawActions
var state = AppState()
for action in actions { state = reduce(state, action) }
clean += 1
if pinSequence != nil { break }                 // single-shot
```

**Why always draw.** The Xoshiro256** state needs to advance the
same way as the original failing run, otherwise the replayed
sequence would have different actions. Drawing-then-skipping
preserves the trajectory.

**Why `break` after one execution.** Pinned mode is the shrinker's
re-invocation primitive — we want exactly one execution per
binary invocation so the exit code is unambiguous: trap during the
pinned sequence → non-zero, clean → zero.

`VerifierSubprocess.runVerifierBinary` gains an `extraEnvironment:
[String: String] = [:]` parameter that merges over the inherited
DYLD_LIBRARY_PATH-augmented environment. Caller's entries win on
conflict, matching the convention in
`environmentWithTestingLibraryPath`.

## M8.D.3 — Binary-search shrinker

`InteractionShrinker.shrinkPrefix` finds the minimum prefix length
that still causes a trap:

```swift
var low = -1                  // largest known-passing prefix
var high = upperBound         // smallest known-trapping prefix
while low + 1 < high {
    let mid = (low + high) / 2
    let exitCode = runner.invoke(failingSequenceIndex, mid)
    if exitCode != 0 { high = mid } else { low = mid }
}
return high
```

**Why `low = -1` initially.** We don't *know* that any length
passes; the only thing we know is that `upperBound` traps (the
original failing run). The invariant is "all lengths `≤ low`
pass; all lengths `≥ high` trap." Starting at `low = -1`
correctly handles the boundary case where even the empty action
list traps (`shrinkPrefix` returns 0).

**Closure-shaped Runner.** The `Runner` struct wraps a closure
`(Int, Int) -> Int32` so unit tests inject synthetic threshold-
bearing logic without spawning real binaries. `liveRunner(workdir:)`
provides the concrete binding to `VerifierSubprocess`.

**O(log N) re-invocations.** For `upperBound = 16`, at most ⌈log₂
17⌉ = 5 invocations. Each invocation builds nothing (workdir
already built); just runs the binary with new env vars. Total
shrink time on a small reducer is dominated by 5 × verifier-binary
startup, typically under a second.

`InteractionTraceEmitter.Inputs.minimumFailingPrefixLength`
threads the shrink result into the trace's replay body. When
supplied:

```swift
let rawActions = generator.run(using: &rng)
let actions = Array(rawActions.prefix(3))   // shrunk to 3
```

## What M8.D doesn't do (yet)

**Drop-prefix shrinking** (chopping from the head, not the tail).
The stub only exposes prefix-length truncation at M8.D.2. Adding
a `SWIFT_INFER_PIN_SUFFIX_START` env var + matching stub logic
would let the shrinker also search for the smallest suffix that
traps:

```swift
// hypothetical M8.D.4
let pinStart = env["SWIFT_INFER_PIN_SUFFIX_START"].flatMap(Int.init) ?? 0
let actions = pinStart > 0
    ? Array(rawActions[pinStart...])
    : rawActions
```

Combined drop-prefix + drop-suffix shrinking would converge to a
minimal sub-sequence. The drop-suffix-only posture this cycle ships
handles trajectories where the trap-relevant actions cluster early —
common but not universal.

**Effect-bearing-reducer corpus signal.** PRD line 731 requires "at
least 1 effect-bearing reducer produces `.bothPass`." Still gated
on the v2.2.0 kit publication; M8.A unblocks the emit path
end-to-end but synthesized workdirs return
`.architecturalCoveragePending` until the kit tag goes to remote.

## End-to-end shape of a failing-trace replay

```
verify-interaction --target MyApp --reducer Inbox.body
↓ M3.E builds + runs the verifier binary
↓ Reducer traps at sequence 41, action 7
↓ M8.D.1 parser recovers failingSequenceIndex = 41
↓ M8.D.3 shrinker re-invokes binary 5× with pin env vars
↓ Finds minimumFailingPrefixLength = 3
↓ M8.C/D persists trace under Tests/Generated/SwiftInferTraces/
↓ Trace burns 41 sequences, replays Array(actions.prefix(3))
```

The user runs `swift test` on the next CI invocation; the trace
replays the 3-action minimum and fails. Once the reducer is fixed,
the same `swift test` passes. The trace can be deleted at that
point, or left in place as a long-term regression guard.

## Test count breakdown

**2870 → 2897 (+27):**

- **M8.D.1:** 2 stub-shape tests (Foundation import, stderr marker
  + `\(sequenceIndex)`); 5 parser tests (failing-index recovery
  happy paths + edge cases + last-marker preference); 3 trace-
  emitter tests (zero / nonzero / nil failing-index branches).
  +10.
- **M8.D.2:** 5 stub-shape tests (env-var reads, skip-non-target,
  prefix truncation, break-after-one, byte-stable env-var names);
  1 VerifierSubprocess smoke test (extraEnvironment doesn't break
  the missing-binary error path). +6.
- **M8.D.3:** 7 shrinker tests (threshold-in-middle / at upperBound
  / at 0 / at 1, log-bound check, sequence-index forwarding,
  bounds-staying); 1 liveRunner smoke test; 3 trace-emitter
  prefix-truncation tests. +11.

§13 budgets unchanged — no scan-perf surface touched.

## What's next — M9 / M10 + M8.D follow-ups

PRD §5.8's remaining arc:

- **M9 — InteractionInvariantBridge.** Kit-side
  `InteractionInvariant` protocol family + conformance suggestion
  when ≥ 3 Strong-tier interaction invariants fire on the same
  reducer. Cross-repo coordination — needs a SwiftPropertyLaws
  kit minor bump (`v2.3.0`) alongside the still-pending v2.2.0
  publication.
- **M10 — Drift mode** for interaction invariants. Per-baseline
  warning on new Strong-tier interaction suggestions added since
  baseline. Mirrors v1's drift mechanism.

M8.D follow-ups queued:
1. **Drop-prefix shrinking** via `SWIFT_INFER_PIN_SUFFIX_START`
   env var + matching stub logic. Combined with M8.D.3's
   drop-suffix to produce minimal sub-sequences.
2. **`accept-check`-shaped flow** for interaction invariants —
   v1.72's post-acceptance failure rate but keyed on the
   trace-replay regression surface.

Calibration cycles for M5–M7 families can also start in parallel.

## Artifacts

- v1.84 sources:
  - `Sources/SwiftInferCLI/ActionSequenceStubEmitter.swift` (M8.D.1
    stderr marker, M8.D.2 env-var-driven single-sequence replay,
    `makeIterationBody` extract)
  - `Sources/SwiftInferCLI/InteractionVerifyOutcomeParser.swift`
    (M8.D.1 failing-index extractor, stderr-aware parseRunOutput)
  - `Sources/SwiftInferCLI/InteractionTraceEmitter.swift` (M8.D.1
    burn-then-replay-one shape, M8.D.3 prefix-truncation arm)
  - `Sources/SwiftInferCLI/VerifierSubprocess.swift` (M8.D.2
    extraEnvironment parameter)
  - `Sources/SwiftInferCLI/InteractionShrinker.swift` (M8.D.3 new
    file, binary-search + Runner closure shape)
  - `Sources/SwiftInferCLI/VerifyInteractionPipeline.swift` (M8.D.3
    shrinker wired into runPipeline)
- Prior cycle: `docs/calibration-cycle-80-findings.md` (M8 —
  effect-bearing verify path + initial trace persistence).
- v2.0 PRD: `docs/SwiftInferProperties PRD v2.0.md`.
