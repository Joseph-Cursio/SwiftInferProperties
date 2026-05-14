# v1.67 Calibration Cycle 64 — Findings (verify scoring moves before the visibility cut)

Captured: 2026-05-14. swift-infer at v1.67.

## Headline

**Architecture cycle, not a measurement cycle.** v1.67 closes the
documented limitation of v1.66: verify-as-signal now runs *inside* the
discover pipeline, **before** the visibility filter, instead of in the
CLI layer after it. A `bothPass` outcome can now lift a pick that scored
sub-threshold on heuristics alone into view — v1.66.B could only
re-grade picks that were already visible.

Cycle-60's **42/103 = 40.8% measured-execution** carries forward
unchanged — v1.67 touches no emitter, resolver, or carrier path.

## The limitation v1.66 left, and the fix

v1.66.B applied `VerifyEvidenceScoring` in `Discover.run`, on
`pipeline.suggestions` — which is *already* filtered for visibility by
`combineAndFilter`. A `.possible`-tier pick (score 20–39) was dropped
before the post-pass ever saw it, so even a `bothPass` outcome couldn't
surface it without `--include-possible`.

v1.67 moves the fold one step earlier:

- `collectVisibleSuggestions` gains a `verifyEvidenceByIdentity`
  parameter (defaulted `[:]`, so the ~53 non-`discover` callers —
  `drift`, `index`, the integration tests — are untouched). It threads
  to `combineAndFilter`, which applies `VerifyEvidenceScoring.applied`
  to the combined suggestion set *before* the
  `includePossible || isVisibleByDefault` cut.
- `Discover.run` loads the evidence first
  (`VerifyEvidenceStore.load(startingFrom: directory)` walks up for the
  package root itself, so the load doesn't depend on the pipeline
  result) and passes the map in. The v1.66.B CLI-layer post-pass and
  its explicit `!= .suppressed` filter are removed — the pipeline owns
  both now.

## A bug fixed along the way

Moving the scoring into `combineAndFilter` surfaced — and would have
re-introduced — a filter gap. `combineAndFilter`'s cut was
`includePossible || isVisibleByDefault`; under `--include-possible`
that passes **everything**, including `.suppressed`. v1.66.B had an
*explicit* `!= .suppressed` guard in the CLI layer that masked this;
relying on `combineAndFilter`'s filter alone would have leaked
verify-disproven picks through `--include-possible` — defeating the
v1.66 veto.

`combineAndFilter` now drops `.suppressed` unconditionally, matching
the documented `Tier.suppressed` "never shown" invariant (which
`SuggestionRenderer.renderStats` already assumed). The full 2482-test
suite confirms no existing test relied on `--include-possible` showing
a `.suppressed` pick — i.e. `.suppressed` suggestions were not reaching
that filter in practice before v1.67; the veto is what newly produces
them there.

## What shipped

| Workstream | Summary |
|---|---|
| **V1.67.A** | `collectVisibleSuggestions` + `combineAndFilter` gain the `verifyEvidenceByIdentity` parameter; scoring runs before the visibility cut; `combineAndFilter` drops `.suppressed` unconditionally; `Discover.run` reordered to load evidence first. `DiscoverPipelineVerifyEvidenceTests` (5 tests) pins the rescue + veto + no-op behaviour. |
| **V1.67.B** | Version bump 1.66.0 → 1.67.0, this findings doc, CLAUDE.md "Repository state" update. |

## Confirmed behaviour

Smoke-tested on a real `discover` run against a temp package.
`wrangle(_ value: Int) -> Int { value &+ 1 }` earns only the
`typeSymmetrySignature` signal (+30) → `.possible` tier:

- default, no evidence → **`0 suggestions.`** (hidden).
- default, `bothPass` evidence → **`Score: 80 (Verified)`, `1 suggestion.`**
  — rescued: graded +50 before the cut → `.strong` → visible, and
  v1.65's promotion labels it `.verified`.
- `--include-possible`, `defaultFails` evidence → the pick is **absent**
  (vetoed → `.suppressed` → dropped even under `--include-possible`).

## Scope boundaries

- **`drift` and `index` are unchanged.** They call
  `collectVisibleSuggestions` with the defaulted empty map. Whether a
  verify-disproven suggestion should be excluded from `drift` warnings,
  or whether the `index` should reflect verify-influenced scores, are
  open questions — deferred. The `index` staying on pure heuristic
  scores is arguably correct (it is the catalog; verify evidence is a
  separate join), but `drift` integration is a reasonable follow-up.
- **`interactive` / `update-baseline` do get the scored set** — they
  consume `pipeline.suggestions`, which is now verify-graded. A
  bothPass-boosted pick records its boosted score in `DecisionRecord` /
  `Baseline`; a disproven pick is already gone. This is the intended
  "full verify-as-signal" reach across all `discover` paths.

## Test count

**2477 → 2482 (+5)** — `DiscoverPipelineVerifyEvidenceTests`. §13
budgets unchanged — the post-pass is O(n). Perf baseline is a v1.63
carry-forward.

## What's next (post-v1.67)

The verify-evidence arc (v1.64 persist → annotate → v1.65 tier label →
v1.66 grade → v1.67 grade-before-the-cut) is now complete and
internally consistent. Remaining roadmap:

1. **`.verified` in recorded decisions** — thread the effective tier
   through interactive triage so `DecisionRecord.tier` / `metrics`'
   tier-mix can be `.verified`.
2. **`drift` verify integration** — exclude verify-disproven
   suggestions from drift warnings.
3. **Discover-CLI integration test for verify-suppression** — a
   `Discover.run`-level guard (the V1.67.A tests cover the pipeline
   function; the CLI `run()` wiring is still only smoke-tested).
4. **Monotonicity-emitter rework** — the only remaining real pick
   target (~4 direct + ~6 behind nested-OC scaffolds); a weak trade per
   the cycle-60 investigation.
5. **`metrics` per-corpus evidence join** — extend V1.64.D to explicit
   `--decisions` aggregation mode.
6. **V1.42.C.5 deferred** — implicit reindex on demand (carried from v1.42).

## Artifacts

- v1.67 source: `Sources/SwiftInferCLI/Discover+Pipeline.swift`
  (parameter + scoring + filter fix), `Sources/SwiftInferCLI/SwiftInferCommand.swift`
  (`Discover.run` reorder + version bump).
- Prior cycles: `docs/calibration-cycle-63-findings.md` (v1.66
  verify-as-signal), `docs/calibration-cycle-62-findings.md` (v1.65
  Verified tier), `docs/calibration-cycle-61-findings.md` (v1.64
  accept-flow integration).
