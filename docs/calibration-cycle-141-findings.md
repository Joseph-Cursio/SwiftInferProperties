# Calibration cycle 141 — cardinality verify corpus widened (3 → 5 reducers)

**Captured 2026-06-15.** No binary change — fixtures + test updates. Second
of the corpus-widening follow-ups (after cycle 140's conservation). The
original cardinality trio (Router/Drawer/Leaky) used only **Bool-flag**
fields, whose predicate term is `state.<name>`. This widens to cover the
**Optional-presentation** indicator (`state.<name> != nil`) and the
**≥3-field** witness — the parts of the `Σ indicators <= 1` vocabulary the
all-Bool trio didn't exercise.

## What shipped

`Tests/Fixtures/cardinality-verify-corpus/` gains two real `@Reducer`s
(`.tca`), both **all-Optional** (a Bool + Optional pair would also surface
biconditional; two-plus Optionals with no Bool stay cardinality-only):

- **SheetRouterFeature** — two Optional presentation fields (`activeSheet`,
  `activeAlert`), mutex enforced, all Action cases payload-free →
  FULL-coverage `measured-bothPass` → the Finding-G pin is OVERRULED →
  `.verified`. Exercises the `!= nil` indicator in the overrule path.
- **PopoverFeature** — THREE Optional fields (`activeSheet`, `activeAlert`,
  `activePopover`) → a single witness summing three `!= nil` indicators;
  the reducer does NOT enforce the mutex → `measured-defaultFails` →
  suppressed. Exercises the richer ≥3-field witness and the Optional
  indicator in the defaultFails path.

## Measured baseline

`verify-interaction --all --family cardinality` now: **5 identities → 3
`measured-bothPass` + 2 `measured-defaultFails`**:

- RouterFeature (Bool, full) → `.verified` (overrule)
- DrawerFeature (Bool, partial — `received(Data)` excluded) → stays
  `.possible`
- SheetRouterFeature (Optional, full) → `.verified` (overrule)
- LeakyFeature (Bool, no mutex) → suppressed
- PopoverFeature (3× Optional, no mutex) → suppressed

So the full-coverage overrule now holds across **both** indicator forms
(Bool `state.x` and Optional `state.x != nil`), and the coverage gate
(Drawer stays Possible) and false-positive suppression (Leaky + Popover)
both hold across them too — coverage breadth, not just count.

## Verification

- **Fast:** `CardinalityVerifyCorpusTests` (~0.5s) — discovery surfaces
  exactly the five cardinality identities at `.possible`, asserting both
  indicator forms in the predicates; no other family.
- **Measured (`.subprocess`):** `CardinalityVerifyCorpusMeasuredTests`
  (~72s — warm workdir absorbs the two extra builds) — 5 → 3 bothPass + 2
  defaultFails; discover promotes Router + SheetRouter to `(Verified)` with
  the overrule disclosure, keeps Drawer at `(Possible)`, suppresses Leaky +
  Popover.
- `swiftlint` clean.

## What's next

Unchanged — all off the critical path: further corpus widening (biconditional
/ refint / idempotence-tca remain candidates), the shelved value-generator
(c119) / `.tca` C1 (c126) items, and `IdentifiableResolver` precision edges.
The frozen 50.5% measured-execution rate stays a discovery-corpus metric.
