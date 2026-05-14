# v1.65 Calibration Cycle 62 — Findings (Verified first-class tier)

Captured: 2026-05-14. swift-infer at v1.65.

## Headline

**Architecture cycle, not a measurement cycle.** v1.65 ships the
**`Tier.verified` first-class tier** — `discover` now *acts* on verify
evidence, not just annotates it (v1.64.C). A `.strong` suggestion whose
`swift-infer verify` run reached `.measuredBothPass` is presented as
`Verified`: the top tier, floated to the head of the discover stream.

No new full-surface survey was run; cycle-60's **42/103 = 40.8%
measured-execution** carries forward unchanged (v1.65 touches no
emitter, resolver, or carrier path). This is the v1.65+ priority #1
from `docs/calibration-cycle-61-findings.md`.

## What shipped — two workstreams

| Workstream | Summary |
|---|---|
| **V1.65.A** | `Tier.verified` case, first in `Tier.allCases` (`verified > strong > likely > possible > suppressed > advisory`). `Tier.promoted(byVerifyOutcome:)` resolves the effective tier: `.strong` + `.measuredBothPass` → `.verified`; every other `(tier, outcome)` pair, and a `nil` outcome, is unchanged. `SuggestionRenderer` renders the *effective* tier in the `Score:` line; score total is untouched. Promotion is render-time only — `.verified` never reaches `Tier(score:)`, `DecisionRecord.tier`, or `Baseline.tier`. |
| **V1.65.B** | `SuggestionRenderer.verifiedFirst` — a stable partition floating `.verified` suggestions to the head of the stream, relative order preserved within both groups. The list renderer applies it before emitting blocks; an empty evidence map promotes nothing, so input order and existing goldens are unchanged. |
| **V1.65.E** | Version bump 1.64.0 → 1.65.0, this findings doc, CLAUDE.md "Repository state" update. |

## What "Verified" means, and what it deliberately is not

`Verified` = **human-signal-strong AND machine-confirmed**. Only
`.strong` (score ≥ 75) promotes — a `.likely` pick that verifies as
`bothPass` keeps its `Verify: ✓ bothPass` annotation (v1.64.C) but
stays `.likely`. This is the conservative bar: `Verified` is the *top*
tier, not a synonym for "ran clean."

Deliberate non-goals this cycle (recorded so they aren't mistaken for
oversights):

1. **`.verified` is render-time only.** It is not baked into `Score`,
   not recorded in `DecisionRecord.tier` / `Baseline.tier`. The
   `Score`-building pipeline runs before verify evidence is loaded; a
   score-participating model would need a pipeline reorder. The
   render-time tier is the minimal, architecture-respecting cut.
2. **No score change.** A promoted suggestion still shows
   `Score: 90 (Verified)` — the total is the human-signal score; the
   tier label is what moves.
3. **`defaultFails` does not demote or suppress.** Per the cycle-61
   design decision and PRD §3.5 — `discover` renders the prominent
   `✗ defaultFails (verify-disproven)` annotation, but the suggestion
   keeps its base tier and the user still decides.

## Blast radius

Adding a `Tier` case touched three compiler-enforced exhaustive
switches — `Tier.label`, `Tier.isVisibleByDefault`,
`IndexCommand.humanReadableTier` — and nothing else. `Tier.allCases`
gains `.verified` (first); `MetricsRenderer.tierRows` `compactMap`s it
away when no decisions sit at that tier, which is always the case while
promotion stays render-time. Discover does not tier-sort the base
stream, so V1.65.B's `verifiedFirst` is the only ordering change, and
it is a no-op without evidence.

## Test count

**2461 → 2471 (+10)**:

- V1.65.A: +7 (`TierTests` +3, `SuggestionRendererVerifyEvidenceTests` +4)
- V1.65.B: +3 (`SuggestionRendererVerifyEvidenceTests`)

Confirmed on a real `discover` run: a Strong idempotence pick with a
hand-written `bothPass` evidence record renders `Score: 90 (Verified)`
and is floated above an unverified `Likely` pick. Existing goldens are
byte-identical (no evidence → base tier, input order). §13 budgets
unchanged — `verifiedFirst` is an O(n) in-memory partition. The full
2471-test parallel run flaked twice on thin-margin §13 perf budgets
(~2.02s vs 2.0s) under load; the Performance suite passes clean in
isolation. Perf baseline is a v1.63 carry-forward.

## What's next (post-v1.65)

1. **Verify-as-signal (score participation)** — the v1.65 alternative
   not taken: verify evidence as a `Signal` feeding `Score`, which
   needs the discover pipeline to load evidence before scoring. Larger,
   but makes verify part of the grade rather than a render-time
   overlay.
2. **`.verified` in recorded decisions** — thread the effective tier
   through interactive triage so `DecisionRecord.tier` can be
   `.verified` and `metrics`' tier-mix table reflects it.
3. **Monotonicity-emitter rework** — the only remaining real pick
   target (~4 direct + ~6 behind nested-OC scaffolds); a weak trade per
   the cycle-60 investigation.
4. **`metrics` per-corpus evidence join** — extend V1.64.D's
   cross-reference to explicit `--decisions` aggregation mode.
5. **V1.42.C.5 deferred** — implicit reindex on demand (carried from v1.42).

## Artifacts

- v1.65 source: edits to `Sources/SwiftInferCore/Tier.swift`,
  `Sources/SwiftInferCore/SuggestionRenderer.swift`,
  `Sources/SwiftInferCLI/IndexCommand.swift`,
  `Sources/SwiftInferCLI/SwiftInferCommand.swift`.
- Scoping: the AskUserQuestion fork in the v1.65 working session chose
  the `Tier.verified` approach over an orthogonal overlay or
  verify-as-signal.
- Prior cycle: `docs/calibration-cycle-61-findings.md` (v1.64 Phase 2
  accept-flow integration).
