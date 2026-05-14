# v1.66 Calibration Cycle 63 — Findings (verify-as-signal; overturns the "defaultFails does not demote" decision)

Captured: 2026-05-14. swift-infer at v1.66.

## Headline

**Architecture cycle, not a measurement cycle.** v1.66 ships
**verify-as-signal** — persisted `swift-infer verify` outcomes now
participate in the suggestion *grade*, not just the rendered
annotation (v1.64.C) or the render-time tier label (v1.65). A
`measuredBothPass` outcome adds a heavy positive signal; a
`measuredDefaultFails` outcome is a **veto** — the disproven suggestion
collapses to `.suppressed` and `discover` drops it.

This **deliberately overturns the cycle-61/62 design decision** that
"defaultFails does not demote or suppress." The rationale is in its own
section below; it is the load-bearing decision of this cycle.

Cycle-60's **42/103 = 40.8% measured-execution** carries forward
unchanged — v1.66 touches no emitter, resolver, or carrier path.

## The overturned decision, and why

**Cycle-61 design decision #3 / cycle-62 design decision #3:**
*"`defaultFails` does not demote or suppress. Per PRD §3.5 — `discover`
renders the prominent `✗ defaultFails` annotation, but the suggestion
keeps its base tier and the user still decides."*

**v1.66 overturns this.** The reasoning:

The cycle-61/62 decision invoked PRD §3.5's conservatism — the "Daikon
trap": a tool that emits too many *speculative, heuristic* guesses
drowns the user and loses trust. That conservatism is correct, and it
is why every *heuristic* signal (name match, type symmetry, body
patterns) is weighted carefully and why "when in doubt, fewer
suggestions."

But `defaultFails` is **not a heuristic guess.** It is an *executed
counterexample*: the synthesized property test was compiled, run, and
**mathematically failed** on a concrete input. A suggestion with a
`defaultFails` outcome is not low-confidence — it is *known false*.

Surfacing a known-false suggestion is a true false positive. Suppressing
it **raises** precision; it is the opposite of the Daikon trap. The
cycle-61/62 decision conflated *execution evidence* with *heuristic
inference* — applying heuristic-grade caution to a measured result.
v1.66 corrects that conflation. The conservative posture of PRD §3.5 is
*served*, not violated, by vetoing disproven suggestions.

(`docs/calibration-cycle-61-findings.md` and
`docs/calibration-cycle-62-findings.md` carry a retroactive note
pointing here.)

## What shipped — three workstreams

| Workstream | Summary |
|---|---|
| **V1.66.A** | `Signal.Kind.verifyBothPass` (heavy positive) + `Signal.Kind.verifyDisproven` (veto). `VerifyEvidenceScoring.applied` — a pure, order-preserving post-pass that folds persisted outcomes into suggestion `Score`s: `bothPass` → `+50` signal joining `whySuggested`; `defaultFails` → veto signal joining `whyMightBeWrong`; `edgeCaseAdvisory` / `measuredError` / `architecturalCoveragePending` score-neutral; `.advisory`-tier suggestions skipped (no runnable property). `Suggestion.appendingScoreSignal` rebuilds the immutable `Score` + `ExplainabilityBlock` — the score pipeline runs before evidence loads, so the signal joins by rebuild. |
| **V1.66.B** | `Discover.run` loads `verify-evidence.json` once near the top and applies `VerifyEvidenceScoring` ahead of every downstream path (render / interactive / update-baseline); `.filter { $0.score.tier != .suppressed }` drops the vetoed picks. The V1.64.C render block was hoisted to reuse the single load. |
| **V1.66.E** | Version bump 1.65.0 → 1.66.0, this findings doc, retroactive notes on cycles 61–62, CLAUDE.md "Repository state" update. |

## The weight: +50 for `verifyBothPass`

`verifyBothPassWeight = 50` — heavier than any single heuristic signal
(the largest of those are +40–50). An executed, passed property is the
strongest single piece of evidence the system can hold. +50 lifts even
a bare exact-name-match pick (+40 → Likely) past the Strong threshold
(75 → 90), and a Strong pick into clear Strong/Verified territory.

`verifyDisproven` uses `Signal.vetoWeight` — the existing veto sentinel;
`Score` collapses any vetoed signal to `.suppressed`.

## How v1.64 / v1.65 / v1.66 compose

The three cycles layer cleanly on a `bothPass`-verified Strong pick:

- **v1.64.C** — a `Verify: ✓ bothPass` annotation line in the block.
- **v1.66** — a `+50 verifyBothPass` signal: `Score: 90 → 140`, and a
  `Verify: bothPass — … (+50)` bullet in `whySuggested`.
- **v1.65** — the effective tier promotes `.strong` → `.verified`, and
  the block floats to the head of the stream.

A `defaultFails` pick: v1.64.C would annotate it, but v1.66 vetoes it
first, so it never reaches the renderer at all.

## Confirmed behaviour

Smoke-tested on a real `discover` run against a temp package (Strong
idempotence pick, base `Score: 90`):

- `defaultFails` evidence → **`0 suggestions.`** — vetoed and dropped.
- `bothPass` evidence → **`Score: 140 (Verified)`** + the `+50` bullet
  in `whySuggested`.

## Test count

**2471 → 2477 (+6)** — `VerifyEvidenceScoringTests` (bothPass boost,
defaultFails veto, score-neutral outcomes, no-evidence pass-through,
advisory-skip, order preservation). V1.66.B is thin glue over A's
unit-tested post-pass + the confirmed smoke test; the discover CLI test
harness is not currently set up to drive `run()` with an evidence file
present. §13 budgets unchanged — the post-pass is O(n). Perf baseline
is a v1.63 carry-forward.

## Known limitations / what's next

1. **A `bothPass` outcome cannot rescue a sub-threshold pick.** The
   post-pass runs on `pipeline.suggestions`, which is *already* filtered
   for visibility. A pick that scored below the Possible threshold on
   heuristics alone was dropped before the post-pass — even a
   `bothPass` outcome can't surface it (without `--include-possible`).
   The full fix is a discover-pipeline reorder: load evidence and score
   it *before* the visibility filter. Deferred to a future cycle.
2. **`discover` stdout is now a function of `verify-evidence.json`.** An
   intentional extension of the PRD §16 reproducibility contract, begun
   by v1.64.C (annotation) and v1.65.B (ordering), completed here
   (membership + score). Documented, not a regression.
3. **A discover-CLI integration test for verify-suppression** would be a
   good permanent regression guard for the headline behaviour.
4. **Monotonicity-emitter rework** — the only remaining real pick target
   (~4 direct + ~6 behind nested-OC scaffolds); a weak trade per the
   cycle-60 investigation.
5. **`metrics` per-corpus evidence join** — extend V1.64.D's
   cross-reference to explicit `--decisions` aggregation mode.
6. **V1.42.C.5 deferred** — implicit reindex on demand (carried from v1.42).

## Artifacts

- v1.66 source: `Sources/SwiftInferCore/Signal.swift` (+2 kinds),
  `Sources/SwiftInferCore/VerifyEvidenceScoring.swift` (new),
  `Sources/SwiftInferCLI/SwiftInferCommand.swift` (discover wiring +
  version bump).
- Prior cycles: `docs/calibration-cycle-62-findings.md` (v1.65 Verified
  tier), `docs/calibration-cycle-61-findings.md` (v1.64 accept-flow
  integration).
