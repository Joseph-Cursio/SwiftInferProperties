# Calibration cycle 140 — conservation verify corpus widened (2 → 4 reducers)

**Captured 2026-06-15.** No binary change — fixtures + test updates. The
first of the off-critical-path "corpus widening" follow-ups. Conservation
was the thinnest verify corpus (2 reducers / 2 identities); this widens it
to 4, adding a true-positive *mechanism* and a false-positive *bug shape*
the original pair didn't cover.

## What shipped

`Tests/Fixtures/conservation-survey-corpus/` gains two plain-struct reducers
(no TCA → the measured test stays ~34s, the warm workdir absorbing the two
extra builds):

- **CartReducer** — a second genuinely-conserving reducer using a DIFFERENT
  maintenance mechanism than InventoryReducer: every transition RECOMPUTES
  the aggregate (`itemCount = lineItems.count`) instead of bumping it in
  lockstep (`count += 1`). Also widens witness vocabulary (`itemCount` /
  `lineItems`). → `measured-bothPass`.
- **RosterReducer** — a second false positive with a DIFFERENT bug shape
  than BadgeReducer: Badge increments WITHOUT appending; Roster keeps the
  pair in sync on `join` but `leaveAll` clears the collection WITHOUT
  resetting the count (clear-without-reset desync). The [join, leaveAll]
  sequence leaves `memberCount > 0` with `members` empty → the per-step
  precondition traps → `measured-defaultFails` → suppressed.

## Measured baseline

`verify-interaction --all --family conservation` now: **4 identities → 2
`measured-bothPass` (Inventory lockstep + Cart recompute) + 2
`measured-defaultFails` (Badge increment-without-append + Roster
clear-without-reset)**. Discover promotes both conservers to `.verified` and
suppresses both false positives. The widening confirms the conservation path
holds across both maintenance mechanisms and catches two distinct desync bug
shapes — coverage breadth, not just count.

## Verification

- **Fast:** `ConservationSurveyCorpusTests` (~0.3s) — discovery surfaces
  exactly the four conservation identities at `.possible`.
- **Measured (`.subprocess`):** `ConservationSurveyCorpusMeasuredTests`
  (~34s) — 4 → 2 bothPass + 2 defaultFails; discover promotes Inventory +
  Cart to `(Verified)`, suppresses Badge + Roster.
- `swiftlint` clean.

## What's next

Unchanged from cycle 139 — all off the critical path: further corpus
widening for any family (volume), the shelved value-generator (c119) /
`.tca` C1 (c126) items, and `IdentifiableResolver` precision edges. The
frozen 50.5% measured-execution rate stays a discovery-corpus metric.
