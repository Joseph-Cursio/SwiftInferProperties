# v1.68 Calibration Cycle 65 — Findings (verify evidence reaches its last two consumers)

Captured: 2026-05-14. swift-infer at v1.69 (the v1.68 work shipped
unversioned and is documented here retroactively; the v1.69 monotonicity
cycle that immediately followed carries the version bump — see
`docs/calibration-cycle-66-findings.md`).

## Headline

**Consumer-completion cycle, not a measurement cycle.** Cycle 64 left
two `discover`-adjacent consumers ignoring verify evidence: the
`metrics` tier-mix (it read the *base* score-derived tier from
`DecisionRecord`, never `.verified`) and `drift` (it called
`collectVisibleSuggestions` with the empty evidence map, so a
verify-disproven pick still tripped a drift warning). Cycle 65 closes
both, plus the Discover-CLI integration-test gap cycle 64 flagged.

Cycle-60's **42/103 = 40.8% measured-execution** carries forward
unchanged — cycle 65 touches no emitter, resolver, or carrier path.

## The two gaps cycle 64 left, and the fixes

### V1.68.A — `.verified` reaches `DecisionRecord.tier`

v1.65 introduced render-time promotion: a `.strong` pick with
`.measuredBothPass` evidence renders as `.verified`. But the contract
was explicitly "render-time only" — interactive triage's `makeRecord`
recorded `suggestion.score.tier`, the *base* tier, so the persisted
`DecisionRecord.tier` (and the `metrics` "tier-mix at decision time"
table that aggregates it) never reflected a verified pick.

V1.68.A threads the evidence map through triage:

- `InteractiveTriage.Context` gains a `verifyEvidenceByIdentity`
  parameter (defaulted `[:]` — non-`discover` callers untouched).
  `Discover.run` passes the map it already loaded for the renderer.
- `makeRecord` records the **effective** tier:
  `suggestion.score.tier.promoted(byVerifyOutcome:)`. A `.strong` pick
  with `.measuredBothPass` evidence now persists as `.verified`.
- `metrics` needed no change — `MetricsRenderer.tierRows` reads
  `DecisionRecord.tier`, which now carries the effective tier.

`Baseline.tier` deliberately keeps the base score-derived tier — a
baseline snapshot is a *pre-verify* surface marker, not a decision. The
`Tier.swift` / `Decisions.swift` docstrings were updated to overturn
the old "render-time only" contract.

### V1.68.B — `drift` excludes verify-disproven suggestions

`Drift.run` now loads `.swiftinfer/verify-evidence.json` (mirroring
`Discover.run`) and threads the evidence map into
`collectVisibleSuggestions`. Because v1.67 applies verify-as-signal
grading *before* the visibility cut, a `defaultFails` veto suppresses
the disproven pick — it never reaches `DriftDetector`, so `drift` no
longer warns on a candidate `discover` already hides. Absent /
unreadable file → empty map → `drift` behaves exactly as pre-v1.68.

### V1.68.C — Discover-CLI integration coverage for verify-suppression

`DiscoverPipelineVerifyEvidenceTests` (v1.67) exercises the pure
`collectVisibleSuggestions` function with an in-memory evidence map.
V1.68.C adds `DiscoverCLIVerifySuppressionTests` — three tests over
real package fixtures that exercise the CLI `Discover.run()` entry
point end-to-end: the `VerifyEvidenceStore.load` disk read of
`.swiftinfer/verify-evidence.json`, the map hand-off into the pipeline,
and the rendered output. A `defaultFails` veto on disk suppresses a
Strong pick from the rendered stream; the veto holds even under
`--include-possible` (the V1.67.A `combineAndFilter` guard); a
`bothPass` record on disk rescues a sub-threshold `.possible` pick into
the default output.

## What shipped

| Workstream | Summary |
|---|---|
| **V1.68.A** | `InteractiveTriage.Context.verifyEvidenceByIdentity`; `makeRecord` records the effective tier; `Discover.run` threads the map. `Tier` / `Decisions` docstrings updated. `InteractiveTriageEffectiveTierTests` pins the promotion + non-promotion + decision-independence cases. |
| **V1.68.B** | `Drift.run` loads + threads verify evidence; `DriftCommandTests` split into `DriftCommandTests` + `DriftDetectionTests` (SwiftLint `type_body_length`); new `driftIsSilentForVerifyDisprovenSuggestions`. |
| **V1.68.C** | `DiscoverCLIVerifySuppressionTests` — three `Discover.run()`-level fixture tests for veto-suppression + bothPass-rescue. |

## Scope completion

The verify-evidence arc — v1.64 persist → annotate → v1.65 tier label →
v1.66 grade → v1.67 grade-before-the-cut — now has **every consumer
wired**: `discover` render (v1.64–v1.65), `discover` grade (v1.66–v1.67),
`metrics` cross-reference + tier-mix (v1.64.D + v1.68.A), and `drift`
(v1.68.B). The cycle-64 "what's next" items #1–#3 are all closed; the
arc is consumer-complete.

## Test count

**2482 → 2490 (+8)** — `InteractiveTriageEffectiveTierTests` (5,
counting the parameterized outcome test as four cases),
`driftIsSilentForVerifyDisprovenSuggestions` (1),
`DiscoverCLIVerifySuppressionTests` (3 — the parameterized
`--include-possible` case counts once). §13 budgets unchanged.

## What's next (post-v1.68)

1. **Monotonicity-emitter rework** — the cycle-64 #4 item; addressed in
   cycle 66 (v1.69), overturning the cycle-60 "defer indefinitely"
   conclusion. See `docs/calibration-cycle-66-findings.md`.
2. **`metrics` per-corpus evidence join** — extend V1.64.D to an
   explicit `--decisions` aggregation mode.
3. **V1.42.C.5 deferred** — implicit reindex on demand (carried from
   v1.42).

## Artifacts

- v1.68 source: `Sources/SwiftInferCLI/InteractiveTriage.swift` +
  `InteractiveTriage+Extraction.swift` (effective tier),
  `Sources/SwiftInferCLI/DriftCommand.swift` (evidence load),
  `Sources/SwiftInferCore/Tier.swift` + `Decisions.swift` (docstring
  contract update).
- Prior cycle: `docs/calibration-cycle-64-findings.md` (v1.67 verify
  scoring before the visibility cut).
