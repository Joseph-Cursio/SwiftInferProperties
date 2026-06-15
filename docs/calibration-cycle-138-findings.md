# Calibration cycle 138 — referential integrity completes the family sweep

**Captured 2026-06-15.** No binary change — fixtures + two tests. The
cycle-137 "what's next": referential integrity, the **fifth and final**
interaction family to get a measured-verify path. With this corpus, **all
five families now promote to `.verified` on measured execution.**

## What shipped

`Tests/Fixtures/refint-verify-corpus/` — two real `@Reducer`s pairing a
`selected*` Optional ID with a collection (one
ReferentialIntegrityWitness apiece, `state.<selected> == nil ||
state.<collection>.contains { $0.id == state.<selected> }`):

- **LibraryFeature** — keeps `selectedBookID` pointing at an existing book
  (or nil): `choose` only ever selects an existing book's id, `wipe` clears
  both. The invariant holds at `State()` and after every action →
  `measured-bothPass`. Refint is **un-gated** (no `swiftProjectLintDeferral`),
  so the bothPass promotes through the normal path (30 + 50 = 80 → `.strong`
  → `.verified`) with **no** pin-overrule disclosure — exactly like
  conservation.
- **CatalogFeature** — the false positive: `removeFirst` drops an item
  WITHOUT fixing the selection, so the sequence [add, choose, removeFirst]
  leaves `selectedItemID` dangling → `measured-defaultFails` → suppressed.

## The `$0.id` predicate compiles (no Identifiable gate needed here)

The cycle-137 note flagged refint's predicate as the one with stub-emit
friction: `contains { $0.id == state.selected }` needs the element type to
expose `id`. **The curated element types (`Book`, `Item`) are
`Identifiable`, so the generated stub compiles directly** — the measured
test verifies this end-to-end. The `$0.id == state.selectedBookID`
comparison (`Int` vs `Int?`) type-checks via Swift's Optional promotion.

**Remaining (genuinely optional, not built):** an `Identifiable`-conformance
gate (or skip) at stub-emit time would let refint verify *arbitrary*
corpora gracefully — a non-Identifiable element currently fails the stub
build (→ `architectural-coverage-pending`, a non-verdict) rather than being
skipped with disclosure. That's a robustness improvement for un-curated
corpora, not required for the family to have a demonstrated path.

## Cross-family hygiene

`selectedBookID` implies element type "Book" (cycle-101a filter), matching
`[Book]`; same for `selectedItemID` × `[Item]`. No count-named Int + array
(conservation), no ≥2 presentation slots (cardinality), no Bool/Optional
pair (biconditional), and action names avoid the idempotence witness
vocabulary — so each reducer surfaces exactly one refint identity.

## Verification

- **Fast (CLI):** `RefIntVerifyCorpusTests` (~0.1s) — discovery surfaces
  exactly the two refint identities at `.possible`, no other family.
- **Measured (`.subprocess`):** `RefIntVerifyCorpusMeasuredTests` (~61s) —
  survey → 1 bothPass + 1 defaultFails; discover promotes Library to
  `(Verified)` (no overrule disclosure — un-gated), suppresses Catalog.
- `swiftlint` clean.

## What's next — the family sweep is complete

All five interaction families now have a demonstrated measured-verify path:

| Family | Gate | Promotion |
|---|---|---|
| idempotence | un-gated | `.likely → .verified` (cycle 118) |
| conservation | un-gated | `.possible → .verified` (cycle 134) |
| cardinality | gated | full-coverage overrule → `.verified` (cycle 136) |
| biconditional | gated | full-coverage overrule → `.verified` (cycle 137) |
| referential integrity | un-gated | `.possible → .verified` (cycle 138) |

No family-coverage work remains. Optional follow-ups: the refint
`Identifiable` stub-emit gate (robustness on un-curated corpora); widening
any family's corpus (volume, not coverage); the long-shelved value-generator
/ `.tca` C1 items. The frozen 50.5% measured-execution rate stays a
*discovery-corpus* metric — orthogonal to this family-coverage arc.
