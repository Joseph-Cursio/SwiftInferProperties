# v1.85 Calibration Cycle 82 — Findings (V2.0.M8.D.4: drop-prefix shrinking)

Captured: 2026-05-15. swift-infer at v1.85.

## Headline

**V2.0.M8.D.4 ships — PRD §7.2 #3's drop-prefix / drop-suffix /
halving class is now complete.** One sub-cycle adds the drop-prefix
half on top of the M8.D.3 drop-suffix foundation:

- Stub reads a new `SWIFT_INFER_PIN_SUFFIX_START` env var.
- Action slice becomes `rawActions.dropFirst(suffixStart).prefix(prefixLength)`.
- `InteractionShrinker.Runner` gains a `suffixStart` axis.
- New `shrinkSuffixStart` phase + new top-level `shrink` orchestrator.
- `InteractionTraceEmitter` emits the combined slice expression.

**Test count 2897 → 2910 (+13).** No §13 budget regression.

Failing traces now reproduce both **shortest and as-late-as-possible**:
the persisted trace replays exactly `rawActions[start..<start+length]`
where `(start, length)` is the largest-start smallest-length window
that still traps. The byte-stable seed (PRD §16 #6) makes this
deterministic — same reducer → same trace.

## What changed

### Stub side

```swift
let pinSequence = env["SWIFT_INFER_PIN_SEQUENCE"].flatMap(Int.init)
let pinPrefix = env["SWIFT_INFER_PIN_PREFIX_LENGTH"].flatMap(Int.init)
let pinSuffixStart = env["SWIFT_INFER_PIN_SUFFIX_START"].flatMap(Int.init)
...
let rawActions = generator.run(using: &rng)
if let pin = pinSequence, sequenceIndex != pin { continue }
let dropped = pinSuffixStart.map { Array(rawActions.dropFirst($0)) } ?? rawActions
let actions = pinPrefix.map { Array(dropped.prefix($0)) } ?? dropped
```

The slicing is bound-safe at the Swift-stdlib level: `dropFirst(N)`
returns an empty slice when `N ≥ count`; `.prefix(M)` returns up
to `M` elements. So pathological env-var combinations
(`suffixStart > rawActions.count`, etc.) produce an empty action
list rather than crashing.

**Why drop-prefix first, then drop-suffix.** Operationally these
commute (slice composition is associative on bounded ranges), but
the chosen order matches the natural reading: "skip the first S,
then take L of what remains." Equivalent to `rawActions[S..<S+L]`
clamped to bounds.

### Shrinker side

`InteractionShrinker.Runner.invoke` now takes three arguments:
`(sequenceIndex, suffixStart, prefixLength) -> Int32`. M8.D.3's
`shrinkPrefix` keeps its semantics but always passes
`suffixStart = 0` to the runner — it's phase 1, searching for the
smallest length that traps starting at the head.

New `shrinkSuffixStart`:

```swift
let maxStart = max(0, upperBound - prefixLength)
var low = 0                   // largest known-trapping start
var high = maxStart + 1       // smallest known-passing start (sentinel)
while low + 1 < high {
    let mid = (low + high) / 2
    let exitCode = runner.invoke(failingSequenceIndex, mid, prefixLength)
    if exitCode != 0 { low = mid } else { high = mid }
}
return low
```

Note the inverted invariant compared to phase 1: here `low` is
trapping and `high` is passing, because we're maximizing rather
than minimizing.

New top-level orchestrator `shrink`:

```swift
let prefixLength = shrinkPrefix(...)       // phase 1
let suffixStart = shrinkSuffixStart(prefixLength: prefixLength, ...)  // phase 2
return ShrinkResult(suffixStart: suffixStart, prefixLength: prefixLength)
```

Total cost: O(log²N) re-invocations. For upperBound=16, that's at
most ⌈log₂ 17⌉ + ⌈log₂ 17⌉ ≈ 10 re-invocations per phase, 20
total. Each invocation is a single binary spawn against the
already-built workdir. Sub-second wall time on a small reducer.

### Algorithm invariant

Phase 2's binary search requires the trap-coverage function over
`start ∈ [0, maxStart]` to be **monotonically true-then-false**.
Phase 1's output makes this hold:

Phase 1 finds the smallest `L` such that `rawActions[0..<L]`
covers the trap. If the trap is action-at-index `K`, that means
`L = K + 1`. Then phase 2 asks: "what's the largest `S` such that
`rawActions[S..<S+L]` still covers index `K`?" The window covers
`K` iff `S ≤ K < S + L`, i.e., `S ≤ K` (since `L > K` means
`S + L > K` for any S ≥ 0). So the coverage function is
`start ≤ K`, which is monotonic and converges to `S = K`.

**What breaks the invariant.** If phase 1 returned an `L` smaller
than `K + 1` (which it won't — phase 1's binary search is exact),
the coverage function would be non-monotonic and phase 2's
answer would be a "largest trapping start *in the lowest
contiguous trapping interval*," which isn't meaningful for
shrinking. The test suite documents this contract explicitly.

## Trace shape

For a trap at action index 7 in a length-16 sequence, the
persisted trace replays:

```swift
@Test func replay() {
    var rng = Xoshiro(seed: (<seed>))
    let generator = ActionSequenceFactory.actionSequence(
        forCaseIterable: AppAction.self,
        length: 0...16
    )
    for _ in 0..<41 {
        _ = generator.run(using: &rng)         // burn passing sequences
    }
    let rawActions = generator.run(using: &rng)
    let actions = Array(rawActions.dropFirst(7).prefix(1))  // minimal window
    var state = AppState()
    for action in actions {
        state = reduce(state, action)
    }
}
```

That single-action `actions[0]` is the trap-bearing action,
isolated. The user reading the trace sees the smallest possible
reproducer.

## What's still deferred

**Alternating-shrink optimality.** Two-phase (drop-suffix then
drop-prefix) finds the optimal window for "single trap-bearing
action" cases. For more complex traps — e.g., "actions A *and* D
together cause the trap, but not A alone or D alone" — the
optimal trace might be `[A, D]` while two-phase shrinking returns
`[A, B, C, D]` (the full window containing both). Standard
QuickCheck shrinkers iterate alternating phases until no further
shrinking succeeds; PRD §7.2 #3 specifies "drop-prefix /
drop-suffix / halving" without mandating optimality. M8.D.4 ships
the canonical two-phase form; iterative refinement could be a
follow-up but the gains are modest for the common case.

**Element-wise shrinking (within an action).** Action enum cases
with payloads (`.insert(id: 42)`) could be shrunk by replacing
the payload with a "smaller" value (e.g., `id: 0`). Out of scope
for M8.D — the kit's `ActionSequenceFactory` doesn't yet expose
a per-action shrinker, and shipping one would be a kit-side
addition.

**Effect-bearing-reducer corpus signal.** Still gated on the
v2.2.0 kit publication (`git push origin v2.2.0` in
`../SwiftPropertyLaws`). Synthesized interaction workdirs return
`.architecturalCoveragePending` until the kit tag goes to remote.

## What's next — M9 / M10 + remaining M8 follow-up

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

One M8 follow-up still queued:
- **`accept-check`-shaped flow** for interaction invariants — the
  v2.0 analog of v1.72's PRD §17.2 5th metric, keyed on the
  trace-replay regression surface.

Calibration cycles for M5–M7 families can also start in
parallel — each new-family M-milestone needs three cycles of
stable acceptance rate before promotion off default-`.possible`.

## Test count breakdown

**2897 → 2910 (+13):**

- **Shrinker:** 4 `shrinkSuffixStart` tests (tail trap, head trap,
  upperBound boundary, window-fills-bound edge); 2 top-level
  `shrink` composition tests (two-phase, head-trap edge case); 1
  `ShrinkResult` Equatable test. +7.
- **Stub:** 3 emission tests (env-var read, dropFirst-before-prefix
  ordering, byte-stable env-var name); 1 existing test updated to
  match the new `Array(dropped.prefix($0))` form. Net +3.
- **Trace emitter:** 3 slicing tests (both axes, suffix-start-only,
  helper-shape).

§13 budgets unchanged — no scan-perf surface touched.

## Artifacts

- v1.85 sources:
  - `Sources/SwiftInferCLI/ActionSequenceStubEmitter.swift`
    (M8.D.4 `pinSuffixStartEnvVar` constant, drop-prefix slice
    in `makeIterationBody`)
  - `Sources/SwiftInferCLI/InteractionShrinker.swift` (M8.D.4
    `Runner.invoke` 3-arg signature, `shrinkSuffixStart`, top-
    level `shrink`, `ShrinkResult`)
  - `Sources/SwiftInferCLI/InteractionTraceEmitter.swift` (M8.D.4
    `minimumFailingSuffixStart` Inputs field,
    `makeShrunkActionsExpression` helper)
  - `Sources/SwiftInferCLI/VerifyInteractionPipeline.swift` (M8.D.4
    pipeline switches from `shrinkPrefix` to `shrink`, threads
    both axes to the trace)
- Prior cycle: `docs/calibration-cycle-81-findings.md` (M8.D.1–3 —
  minimal-trace shrinking foundation).
- v2.0 PRD: `docs/SwiftInferProperties PRD v2.0.md`.
