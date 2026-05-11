# Cycle-25 Triage Rubric

Methodology document for v1.28's empirical Possible-tier sampling on the post-v1.27 113-surface. The **sixth empirical-only cycle**.

**Carries cycle-23's per-template criteria for the 10 template classes verbatim** (which carry from cycle-20 / cycle-17 / cycle-14 / cycle-6 verbatim). Edits would compromise cycle-23 ↔ cycle-25 rate-shift comparability. Adds "Post-cycle-23 mechanism context" section documenting cycle 24's suppression layers.

**Companion to** `docs/cycle-23-triage-rubric.md`, `docs/cycle-20-triage-rubric.md`, `docs/cycle-17-triage-rubric.md`, `docs/cycle-14-triage-rubric.md`, `docs/cycle-6-triage-rubric.md` — all unchanged for forensic comparability.

## What we're measuring + caveats

Same as cycle 23:
- Accept / Reject / Unknown per the rubric thresholds.
- Single-runner triage (Claude); public-API + commit-history evidence; no test execution.
- §19 acceptance-rate target: `accept / (accept + reject)` ≥ 70%.

## Post-cycle-23 mechanism context

The cycle-25 sample is drawn from the **v1.27 113-surface**, which has been suppressed 114 → 113 (-0.88%) across one mechanism cycle since cycle 23:

- **Cycle 24 / v1.27** — two workstreams, -1 candidate closed:
  - V1.27.A Sequence-conformance fallback path extension on the V1.21.A IteratorProtocol veto (idempotence-lifted Iterator-like methods). **Projected -2 Algo closures; actual 0** — the Iterator-shape Algo candidates V1.27.A targeted had already been closed by V1.21.A/V1.22.A; documented as infrastructure for future corpora.
  - V1.27.B name-prefix-gated full-veto on inverse-pair direction-counter (-1 OC `bucket(after:) × bucket(before:)` pair).

A v1.27 survivor on **inverse-pair** has cleared 6+ distinct mechanism classes that didn't exist at cycle 20 (cycle-23's 5 layers + V1.27.B).

### Per-template suppression layers cleared at v1.27

**Round-trip** (12 v1.27 candidates) — eight post-cycle-6 mechanism layers cleared (unchanged from cycle 23):
- V1.12.1 / V1.15.1 / V1.16.1 / V1.18.A / V1.21.C / V1.22.B / V1.22.D / V1.24.A.

**Idempotence non-lifted** (5 v1.27 candidates) — eight post-cycle-6 layers cleared (unchanged from cycle 23):
- V1.10.1 / V1.15.1 / V1.16.1 / V1.18.A / V1.21.C / V1.22.C (positive class 14) / V1.24.D / V1.25.A.

**Idempotence-lifted** (7 v1.27 candidates) — five layers (cycle-23 had four; +V1.27.A's Sequence-conformance path):
- V1.21.A / V1.22.A / V1.24.B / V1.24.C / **V1.27.A**.

**Inverse-pair** (2 v1.27 candidates) — six layers (cycle-23 had five; +V1.27.B name-prefix gate):
- five carry-forward + **V1.27.B**.

**Other templates** (commutativity / associativity / monotonicity / identity-element / dual-style-consistency / composition-lifted): no new per-template mechanisms cycle 24.

## Per-template criteria

The 10 template classes' criteria are **carried forward verbatim from `docs/cycle-23-triage-rubric.md`** (which carries verbatim from cycle-20 / cycle-17 / cycle-14 / cycle-6). Refer to `docs/cycle-6-triage-rubric.md` for the canonical per-template criteria.

## Decision JSON schema

Mirrors cycle-23's verbatim:

```json
{
  "version": "cycle-25",
  "raters": ["Claude/single-runner"],
  "captured_at": "2026-05-11",
  "swift_infer_commit": "<v1.27-anchor>",
  "swift_infer_tag": "v1.27.0",
  "rubric_path": "docs/cycle-25-triage-rubric.md",
  "decisions": [...]
}
```

## Cycle-25 vs prior cycles methodology delta

| Aspect | Cycle 6 | Cycle 14 | Cycle 17 | Cycle 20 | Cycle 23 | **Cycle 25** |
|---|---|---|---|---|---|---|
| Surface | 349 | 229 | 335 | 152 | 114 | **113** |
| Sample size | 50 | 50 | 46 | 46 | 40 | **36** |
| Per-template criteria | original | verbatim | verbatim | verbatim | verbatim | **verbatim** carry-forward |
| Post-cycle-N context | n/a | cycles 7-13 | cycles 15+16 | cycles 18+19 | cycles 21+22 | **cycle 24** |

Sample size 36 (lower than prior cycles) reflects the smaller v1.27 surface (113 vs 114 at cycle-23) and the cycle-23 mis-bucketed reclassification (idempotence non-lifted 3 → 5, full coverage absorbs +2; idempotence-lifted 9 → 7, sample 6 unchanged). Sampling rate 31.9% — comparable to cycle 23 (35.1%) and cycle 20 (30.3%); higher density than cycles 6 (14%), 14 (22%), 17 (14%).
