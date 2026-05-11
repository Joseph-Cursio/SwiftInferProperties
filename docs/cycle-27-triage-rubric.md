# Cycle-27 Triage Rubric

Methodology document for v1.30's empirical Possible-tier sampling on the post-v1.29 109-surface. The **seventh empirical-only cycle**.

**Carries cycle-25's per-template criteria for the 7 non-empty template classes verbatim** (which carry from cycle-23 / cycle-20 / cycle-17 / cycle-14 / cycle-6). Edits would compromise cycle-25 ↔ cycle-27 rate-shift comparability. Adds "Post-cycle-25 mechanism context" section documenting cycle 26's three suppression layers.

**Companion to** `docs/cycle-25-triage-rubric.md`, `docs/cycle-23-triage-rubric.md`, `docs/cycle-20-triage-rubric.md`, `docs/cycle-17-triage-rubric.md`, `docs/cycle-14-triage-rubric.md`, `docs/cycle-6-triage-rubric.md` — all unchanged for forensic comparability.

## What we're measuring + caveats

Same as cycle 25:
- Accept / Reject / Unknown per the rubric thresholds.
- Single-runner triage (Claude); public-API + commit-history evidence; no test execution.
- §19 acceptance-rate target: `accept / (accept + reject)` ≥ 70%.

## Post-cycle-25 mechanism context

The cycle-27 sample is drawn from the **v1.29 109-surface**, which has been suppressed 113 → 109 (-3.5%) across one mechanism cycle since cycle 25:

- **Cycle 26 / v1.29** — three independently-mergeable workstreams, -4 candidates closed (exact plan-vs-actual match):
  - V1.29.A inverse-pair asymmetric-pair full-veto: extends V1.27.B's name-prefix gate to fire on (cursor-advance × non-direction) asymmetric pairs (-2 OC).
  - V1.29.B identity-element algebraic-family mismatch veto: new `IdentityOperatorAlgebra` curated additive/multiplicative operator-name sets; fires when `T.zero` pairs with non-additive op or `T.one` with non-multiplicative op (-1 CM; new mechanism class 15).
  - V1.29.C composition-lifted monotone-bounded full-veto promotion: V1.21.B's -25 counter promoted to `Signal.vetoWeight` per 4-cycle-stable-reject empirical evidence (-1 OC).

A v1.29 survivor on **the 7 non-empty templates** has cleared 6+ distinct mechanism classes (cycle-25's 5 layers + V1.29.A/B/C for inverse-pair / identity-element / composition-lifted, though those classes are now empty).

### Per-template suppression layers cleared at v1.29

**Round-trip** (12 v1.29 candidates) — eight post-cycle-6 mechanism layers cleared (unchanged from cycle 25).

**Idempotence non-lifted** (5 v1.29 candidates) — eight post-cycle-6 layers cleared (unchanged from cycle 25).

**Idempotence-lifted** (7 v1.29 candidates) — five layers (unchanged from cycle 25).

**Other 4 templates** (monotonicity / commutativity / associativity / dual-style-consistency): no new per-template mechanisms cycle 26.

**Empty templates** (inverse-pair / identity-element / composition-lifted): zero picks on cycle-1..14 corpora; future corpora may surface picks against the new gates.

## Per-template criteria

The 7 non-empty template classes' criteria are **carried forward verbatim from `docs/cycle-25-triage-rubric.md`** (which carries verbatim from cycle-23 / cycle-20 / cycle-17 / cycle-14 / cycle-6). Refer to `docs/cycle-6-triage-rubric.md` for the canonical per-template criteria.

## Decision JSON schema

Mirrors cycle-25's verbatim:

```json
{
  "version": "cycle-27",
  "raters": ["Claude/single-runner"],
  "captured_at": "2026-05-11",
  "swift_infer_commit": "<v1.29-anchor>",
  "swift_infer_tag": "v1.29.0",
  "rubric_path": "docs/cycle-27-triage-rubric.md",
  "decisions": [...]
}
```

## Cycle-27 vs prior cycles methodology delta

| Aspect | C6 | C14 | C17 | C20 | C23 | C25 | **C27** |
|---|---|---|---|---|---|---|---|
| Surface | 349 | 229 | 335 | 152 | 114 | 113 | **109** |
| Sample size | 50 | 50 | 46 | 46 | 40 | 36 | **32** |
| Per-template criteria | original | verbatim | verbatim | verbatim | verbatim | verbatim | **verbatim** carry-forward |
| Post-cycle-N context | n/a | 7-13 | 15+16 | 18+19 | 21+22 | 24 | **26** |

Sample size 32 reflects the smaller v1.29 surface (109 vs 113 at cycle-25) and the rebalanced stratification across 7 non-empty templates (vs 10 at cycle-25). Sampling rate 29.4% — comparable to cycle 25 (31.9%) and cycle 20 (30.3%).
