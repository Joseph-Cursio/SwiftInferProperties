# Calibration cycle 105 findings — second triage datapoint

> **STATUS: COMPLETE.** Second triage datapoint captured at HEAD
> `7f82052` (Finding G cross-reference shipped). 51 unique identities
> triaged: **idempotence 39/39 = 100%** — the promotion gate holds, so
> the `.possible → .likely` counter advances to **2/3**. Overall 90%
> (44/49 decided). The corpus is byte-identical to cycle 104 (same 51
> identity hashes, unchanged reducer source), so this is a clean second
> independent datapoint that reproduces every cycle-104 per-family rate
> exactly. No new findings surfaced. Captured 2026-06-14.

## Purpose

Second of the three triage datapoints (104 → 105 → 106) that gate the
PRD §3.5 promotion of **idempotence** from default-`.possible` to
`.likely`. Cycle 104 started the counter at **1/3 (idempotence 100%,
39/39)**. Cycle 105 only needs to **re-confirm idempotence ≥ 70%** to
advance the counter to 2/3; if 106 also holds, the `.possible → .likely`
promotion is proposed in the cycle-106 findings doc.

Cardinality + biconditional are **off the promotion track** as of cycle
104 (Finding G re-home). They are still triaged and recorded here for
completeness, but their acceptance rate does not gate any promotion. As
of `7f82052` their suggestion output carries the new SwiftProjectLint
cross-reference caveat (`mutually-exclusive-presentation-state` /
`flag-optional-pair-state`) in `whyMightBeWrong`.

## What changed since cycle 104

- **Finding G option a′ shipped (`7f82052`).** Cardinality + biconditional
  now cross-reference the SwiftProjectLint refactor lints in their
  `whyMightBeWrong` block, single-sourced via
  `InteractionInvariantFamily.swiftProjectLintDeferral`. Output still
  emits the property (never deferred/suppressed); hard-pinned at
  `.possible`. Verified live in this cycle's raw output (all 13
  cardinality+biconditional occurrences carry the caveat).
- No detector changes. Same 51 identity hashes as cycle 104 → the corpus
  is unchanged; this is a clean second independent triage of the same
  population.

## Effective denominator (verified at HEAD `7f82052`, 2026-06-14)

| Corpus | Occurrences | Unique identities | Notes |
|---|---:|---:|---|
| HandRolled | 15 | 15 | `Tests/Fixtures/v2.0-corpus`, target HandRolled |
| TCA 1.25.5 (5 targets) | 31 | 31 | CaseStudies 20 / UIKit 5 / SyncUps 2 / Todos 1 / VoiceMemos 3 |
| TCA 1.0.0 (2 targets) | 24 | 24 | CaseStudies 19 / UIKit 5 |
| **Aggregated (cross-corpus dedupe)** | **70** | **51** | identical to cycle 104 |

Occurrence-level family split (pre-dedupe): 55 idempotence / 8
biconditional / 5 cardinality / 1 conservation / 1 referential-integrity
= 70. Matches the cycle-104 worksheet exactly.

**Pre-triage environment audit:**

- Occurrence counts reproduce exactly (HandRolled 15, TCA 1.25.5 31, TCA
  1.0.0 24 → 70).
- All 51 unique identity hashes reproduce — raw outputs persisted to
  `docs/calibration-cycle-105-data/{handrolled,tca-25,tca-10}-raw.txt`.
- Binary built clean (`swift build`, exit 0). Corpora Sources intact
  (tca-25: 69 `.swift`; tca-10: 45 `.swift`), workdirs under the
  purge-safe `$HOME/xcode_projects/calibration-corpora/`.

## Workflow (same as cycle 104)

```sh
BIN="$PWD/.build/debug/swift-infer"
CORPORA="$HOME/xcode_projects/calibration-corpora"

# 1. HandRolled
cd Tests/Fixtures/v2.0-corpus
"$BIN" discover-interaction --target HandRolled --include-possible --interactive

# 2. TCA 1.25.5
cd "$CORPORA/tca-25-discovery"
for tgt in CaseStudies UIKitCaseStudies SyncUps Todos VoiceMemos; do
  "$BIN" discover-interaction --target "$tgt" --include-possible --interactive
done

# 3. TCA 1.0.0
cd "$CORPORA/tca-10-discovery"
for tgt in CaseStudies UIKitCaseStudies; do
  "$BIN" discover-interaction --target "$tgt" --include-possible --interactive
done

# 4. Aggregate
cd /Users/joecursio/xcode_projects/SwiftInferProperties
"$BIN" metrics-interaction \
  --decisions Tests/Fixtures/v2.0-corpus/.swiftinfer/interaction-decisions.json \
  --decisions "$CORPORA/tca-25-discovery/.swiftinfer/interaction-decisions.json" \
  --decisions "$CORPORA/tca-10-discovery/.swiftinfer/interaction-decisions.json"
```

## Cycle 105 aggregated metrics

Rendered by `metrics-interaction` across the three per-corpus decision
files (raw table persisted to
`docs/calibration-cycle-105-data/metrics-aggregated.md`):

| Family | Accepted | AsConformance | Rejected | Skipped | Acceptance rate | Skip rate |
|---|---:|---:|---:|---:|---:|---:|
| Idempotence | 30 | 9 | 0 | 0 | **100%** | 0% |
| Biconditional | 2 | 0 | 4 | 0 | 33% | 0% |
| Cardinality | 0 | 1 | 1 | 2 | 50% | 50%* |
| Referential Integrity | 0 | 1 | 0 | 0 | 100% | 0% |
| Conservation | 0 | 1 | 0 | 0 | 100% | 0% |
| **Overall** | **32** | **12** | **5** | **2** | **90%** | 4% |

_`*` cardinality skip rate > 30% rubric threshold — but the refinement is
the shipped Finding-G SwiftProjectLint re-home, not a rubric bullet (same
disposition as cycle 104)._

Per-corpus decision split (matches cycle 104): HandRolled 12C / 3n; TCA
1.25.5 28A / 2s / 1n; TCA 1.0.0 22A / 1s / 1n.

## Per-family acceptance vs cycle 104

| Family | C104 rate | C105 rate | gate |
|---|---:|---:|---|
| Idempotence | 100% (39/39) | **100% (39/39)** | **held ≥ 70% → counter 2/3** |
| Cardinality | 50% (skip 50%) | 50% (skip 50%) | off-track (Finding G) |
| Biconditional | 33% | 33% | off-track (Finding G) |
| Referential Integrity | 100% (n=1) | 100% (n=1) | thin |
| Conservation | 100% (n=1) | 100% (n=1) | thin |

Every per-family rate reproduces cycle 104 — expected, since the corpus
and reducer source are unchanged and the decisions re-confirm the
cycle-104 grounding (Finding G litmus tests for the structural rows still
hold: cardinality #2 degenerate-accept, the two navigation biconditionals
accept as session artifacts, the rest reject/skip).

## Promotion counter

- **Idempotence:** 104 (100%) → **105 (100%) ✓** → 106 (pending). Counter
  at **2/3**. One more cycle ≥ 70% proposes `.possible → .likely` in the
  cycle-106 findings doc.

## Findings surfaced during triage

**None.** The corpus is byte-identical to cycle 104 (51 matching identity
hashes), so no new detector behavior, no new reducer-grounding surprises.
The only delta from cycle 104 is cosmetic-but-verified: the Finding G
SwiftProjectLint cross-reference now renders in all 13 cardinality +
biconditional suggestion blocks (confirmed in this cycle's raw output),
closing the loop on the `7f82052` change. Cycle 104 closed Findings A–G;
nothing new opens here.

## What's next

| Cycle | What lands |
|---|---|
| 105 | **This file** — second triage datapoint; re-confirm idempotence ≥ 70%. |
| 106 | Third datapoint; idempotence at ≥ 70% across 104+105+106 → propose `.possible → .likely` in cycle-106 findings. |
