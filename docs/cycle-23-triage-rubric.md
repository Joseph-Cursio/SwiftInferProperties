# Cycle-23 Triage Rubric

Methodology document for v1.26's empirical Possible-tier sampling on the post-v1.25 114-surface. The **fifth empirical-only cycle**.

**Carries cycle-20's per-template criteria for the 10 template classes verbatim.** Edits would compromise cycle-20 ↔ cycle-23 rate-shift comparability. Adds "Post-cycle-20 mechanism context" section documenting cycles 21 + 22 suppression layers.

**Companion to** `docs/cycle-20-triage-rubric.md`, `docs/cycle-17-triage-rubric.md`, `docs/cycle-14-triage-rubric.md`, `docs/cycle-6-triage-rubric.md` — all unchanged for forensic comparability.

## What we're measuring + caveats

Same as cycle 20:
- Accept / Reject / Unknown per the rubric thresholds.
- Single-runner triage (Claude); public-API + commit-history evidence; no test execution.
- §19 acceptance-rate target: `accept / (accept + reject)` ≥ 70%.

## Post-cycle-20 mechanism context

The cycle-23 sample is drawn from the **v1.25 114-surface**, which has been suppressed 152 → 114 (-25.0%) across two mechanism cycles since cycle 20:

- **Cycle 21 / v1.24** — four workstreams, -22 candidates closed:
  - V1.24.A asymmetric label class mismatch counter on round-trip (-6 OC).
  - V1.24.B mutator blocklist (reverse/removeFirst/removeLast/pop*/drop*) veto on idempotence-lifted (-9 OC).
  - V1.24.C non-deterministic shuffle veto extension (-3 OC).
  - V1.24.D capacity/formatter shape-disambiguation veto (-4 OC).

- **Cycle 22 / v1.25** — single workstream, -16 candidates closed:
  - V1.25.A index-advance direction-op idempotence veto (-14 OC + -2 Algo).

A v1.25 survivor on **round-trip / idempotence-non-lifted / idempotence-lifted / inverse-pair** has cleared 5+ distinct mechanism classes that didn't exist at cycle 20.

### Per-template suppression layers cleared at v1.25

**Round-trip** (12 v1.25 candidates) — eight post-cycle-6 mechanism layers cleared (cycle-20 had six):
- V1.12.1 / V1.15.1 / V1.16.1 / V1.18.A / V1.21.C / V1.22.B / V1.22.D / **V1.24.A**.

**Idempotence non-lifted** (3 v1.25 candidates) — eight post-cycle-6 layers cleared (cycle-20 had five):
- V1.10.1 / V1.15.1 / V1.16.1 / V1.18.A / V1.21.C / **V1.22.C** (positive class 14) / **V1.24.D** / **V1.25.A**.

**Idempotence-lifted** (9 v1.25 candidates) — four layers (cycle-20 had three):
- V1.21.A / V1.22.A / **V1.24.B** / **V1.24.C**.

**Inverse-pair** (3 v1.25 candidates) — five layers (cycle-20 had five; no cycle-21/22 mechanism touched).

**Other templates** (commutativity / associativity / monotonicity / identity-element / dual-style-consistency / composition-lifted): no new per-template mechanisms cycles 21+22.

## Per-template criteria

The 10 template classes' criteria are **carried forward verbatim from `docs/cycle-20-triage-rubric.md`** (which carries verbatim from cycle-17 + cycle-14 + cycle-6). Refer to that file for the canonical per-template criteria.

## Decision JSON schema

Mirrors cycle-20's verbatim:

```json
{
  "version": "cycle-23",
  "raters": ["Claude/single-runner"],
  "captured_at": "2026-05-10",
  "swift_infer_commit": "<v1.25-anchor>",
  "swift_infer_tag": "v1.25.0",
  "rubric_path": "docs/cycle-23-triage-rubric.md",
  "decisions": [...]
}
```

## Cycle-23 vs prior cycles methodology delta

| Aspect | Cycle 6 | Cycle 14 | Cycle 17 | Cycle 20 | **Cycle 23** |
|---|---|---|---|---|---|
| Surface | 349 | 229 | 335 | 152 | **114** |
| Sample size | 50 | 50 | 46 | 46 | **40** |
| Per-template criteria | original | verbatim | verbatim | verbatim | **verbatim** carry-forward |
| Post-cycle-N context | n/a | cycles 7-13 | cycles 15+16 | cycles 18+19 | **cycles 21+22** |

Sample size 40 (lower than prior cycles) reflects the smaller v1.25 surface (114 vs 152 at cycle-20). Sampling rate 35% — higher density than cycles 6 (14%), 14 (22%), 17 (14%), 20 (30%).
