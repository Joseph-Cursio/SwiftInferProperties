# Calibration cycle 106 findings — third triage datapoint + idempotence promotion proposal

> **STATUS: COMPLETE.** Third and final triage datapoint of the
> idempotence promotion loop, captured at HEAD `080e8a2` (v1.113.0).
> 51 unique identities triaged: **idempotence 39/39 = 100%** for the
> **third consecutive cycle (104 + 105 + 106)** → the PRD §3.5 promotion
> gate is satisfied and this doc **formally proposes promoting idempotence
> from default-`.possible` to `.likely`**. Overall 90% (44/49 decided).
> Corpus byte-identical to cycles 104 + 105 (51 matching identity hashes).
> No new findings. Captured 2026-06-14.

## Purpose

Third of the three triage datapoints (104 → 105 → 106) gating the PRD
§3.5 promotion of **idempotence** from default-`.possible` to `.likely`.
The gate: **≥ 70% acceptance across three consecutive calibration
cycles**. Standings entering this cycle: 104 (100%) → 105 (100%) → 106
(this cycle). A third hold completes the gate and triggers the promotion
proposal below.

## Environment verification (HEAD `080e8a2`, v1.113.0)

- CLI rebuilt clean after the v1.113.0 version bump.
- 70 occurrences (HandRolled 15 / TCA 1.25.5 31 / TCA 1.0.0 24) → **51
  unique identities**.
- **Identity set byte-identical to cycle 105** (`diff` of the sorted
  unique-hash sets is empty — 51/51 match). Raw outputs persisted to
  `docs/calibration-cycle-106-data/{handrolled,tca-25,tca-10}-raw.txt`.
- Finding G SwiftProjectLint cross-reference renders live in all 13
  cardinality + biconditional suggestion blocks.

## Cycle 106 aggregated metrics

Rendered by `metrics-interaction` (raw table:
`docs/calibration-cycle-106-data/metrics-aggregated.md`):

| Family | Accepted | AsConformance | Rejected | Skipped | Acceptance rate | Skip rate |
|---|---:|---:|---:|---:|---:|---:|
| Idempotence | 30 | 9 | 0 | 0 | **100%** | 0% |
| Biconditional | 2 | 0 | 4 | 0 | 33% | 0% |
| Cardinality | 0 | 1 | 1 | 2 | 50% | 50%* |
| Referential Integrity | 0 | 1 | 0 | 0 | 100% | 0% |
| Conservation | 0 | 1 | 0 | 0 | 100% | 0% |
| **Overall** | **32** | **12** | **5** | **2** | **90%** | 4% |

_`*` cardinality skip rate > 30% — disposition is the shipped Finding-G
SwiftProjectLint re-home, not a rubric bullet._

Per-corpus split (matches 104 + 105): HandRolled 12C / 3n; TCA 1.25.5
28A / 2s / 1n; TCA 1.0.0 22A / 1s / 1n.

## Promotion counter — COMPLETE

| Family | C104 | C105 | C106 | Gate (≥70% ×3) |
|---|---:|---:|---:|---|
| **Idempotence** | 100% | 100% | **100%** | ✅ **SATISFIED → promote `.possible → .likely`** |
| Cardinality | 50% | 50% | 50% | off-track (Finding G) |
| Biconditional | 33% | 33% | 33% | off-track (Finding G) |
| Referential Integrity | 100%(n=1) | 100%(n=1) | 100%(n=1) | thin — not a meaningful signal |
| Conservation | 100%(n=1) | 100%(n=1) | 100%(n=1) | thin — not a meaningful signal |

Idempotence is the **only** family with a substantive (n=39) ≥ 70% record
across three consecutive cycles. RefInt + Conservation pass but on n=1 and
do **not** promote (PRD §3.5 needs a meaningful sample; one identity is
not calibration evidence). Cardinality + biconditional are off the
promotion track per Finding G.

## PROMOTION PROPOSAL — idempotence `.possible → .likely`

**Recommendation: promote.** Idempotence has held 100% acceptance (39/39)
across three independent triage cycles on a stable corpus spanning
hand-rolled anchors + two pinned real-world TCA versions. It is
high-precision on real reducer code: every `.binding` / `.delegate` /
`.task` / `.set*` / `.show*` / `.selectTab` / `.refresh` row accepted in
all three cycles. This clears the PRD §3.5 bar.

### Concrete implementation (for cycle 107)

The mechanism is already half-built. Today `InteractionTemplateFamily
.makeSuggestion` hardcodes `tier: .possible` for *every* family (it does
not consult `Tier(score:)`), and `IdempotenceInteractionTemplate
.initialScore = 30` (the `.possible` band, 20..<40). Two coordinated
changes promote idempotence without touching the others:

1. **Bump `IdempotenceInteractionTemplate.initialScore` 30 → 40** (lands
   in the `.likely` band, 40..<75 per `Tier(score:)`).
2. **Make `makeSuggestion` derive tier from score** —
   `tier: family.swiftProjectLintDeferral == nil ? Tier(score: initialScore) : .possible`
   — instead of the hardcoded `.possible`. This is where the Finding G
   `swiftProjectLintDeferral` promotion-gate (shipped `7f82052`) finally
   earns its keep: cardinality + biconditional stay pinned at `.possible`
   even though the global path now derives tier from score; conservation
   + refint stay at `.possible` because their score remains 30.

**Downstream consequences to verify in cycle 107** (do NOT bundle blind):

- `.likely` suggestions surface **without** `--include-possible` — the
  renderer's `filter(_:includePossible:)` shows `.likely` unconditionally.
  This is the intended payoff (idempotence graduates to default
  visibility) but means a `discover-interaction` with no flags will start
  emitting the 39-family idempotence suggestions. Confirm that is wanted
  before shipping.
- Per PRD, `.strong` (not `.likely`) is what unlocks M9 Bridge proposals
  + M10 drift warnings — so this promotion does **not** turn those on. A
  second three-cycle run at ≥ 70% would propose `.likely → .strong`.
- Any golden/snapshot tests pinning idempotence suggestions at
  `Score: 30 (Possible)` will need updating to `40 (Likely)`.

## Findings surfaced during triage

**None.** Corpus byte-identical to cycles 104 + 105 (51 matching identity
hashes); clean third datapoint. Cycle 104 closed Findings A–G.

## What's next

| Cycle | What lands |
|---|---|
| 106 | **This file** — third datapoint; idempotence gate satisfied; promotion proposed. |
| 107 | **Implement the idempotence promotion** (score 30→40 + score-derived tier with the Finding-G gate), verify the downstream visibility consequences, update pinned tests. |
| 108+ | Begin a fresh three-cycle `.likely → .strong` run for idempotence (unlocks M9/M10), or pivot to broadening the corpus for the thin families (RefInt / Conservation). |
