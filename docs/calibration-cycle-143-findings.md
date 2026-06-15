# Calibration cycle 143 — refint verify corpus widened (3 → 5 reducers)

**Captured 2026-06-15.** No binary change — fixtures + test updates. Fourth
corpus-widening follow-up (conservation c140, cardinality c141,
biconditional c142, now refint). The original refint trio
(Library/Catalog/Note) pairs a `selected*` Optional ID with a plain `[T]`
array. This widens to cover TCA's **`IdentifiedArrayOf<T>`** collection and
a second false-positive **bug shape**.

## What shipped

`Tests/Fixtures/refint-verify-corpus/` gains two real `@Reducer`s:

- **PlaylistFeature** — uses `IdentifiedArrayOf<Track>` instead of a plain
  array. The detector recognizes the IdentifiedArray collection (element
  type `Track`), and the emitted `state.tracks.contains { $0.id ==
  state.selectedTrackID }` predicate compiles against it (IdentifiedArray is
  a RandomAccessCollection of Identifiable elements). The reducer keeps the
  selection valid → `measured-bothPass` → un-gated promotion `.possible →
  .verified`. Confirms the refint path works over the idiomatic TCA
  collection, not just `[T]`.
- **GalleryFeature** — a false positive with a DIFFERENT drift than
  CatalogFeature: Catalog *removes* the selected item (remove-dangling);
  Gallery's `.pickGhost` directly sets `selectedPhotoID` to an id that never
  exists (`999`, while photo ids are `0..<count`), so the selection dangles
  from the moment it's set → `measured-defaultFails` → suppressed.

## Measured baseline

`verify-interaction --all --family referential-integrity` now: **5
identities → 2 `measured-bothPass` + 2 `measured-defaultFails` + 1
`architectural-coverage-pending`**:

- LibraryFeature (`[Book]`, valid) → `.verified`
- PlaylistFeature (`IdentifiedArrayOf<Track>`, valid) → `.verified`
- CatalogFeature (`[Item]`, remove-dangling FP) → suppressed
- GalleryFeature (`[Photo]`, select-nonexistent FP) → suppressed
- NoteFeature (non-Identifiable `Note`) → gate-skipped
  (architectural-coverage-pending, **no build**) → stays `.possible`

So the refint path now verifies across both `[T]` and `IdentifiedArrayOf<T>`
collections, suppresses two distinct dangling-selection bug shapes, and the
cycle-139 Identifiable gate still cleanly skips the non-Identifiable case —
coverage breadth, not just count.

## Verification

- **Fast:** `RefIntVerifyCorpusTests` (~0.5s) — discovery surfaces exactly
  the five refint identities at `.possible`, no other family.
- **Measured (`.subprocess`):** `RefIntVerifyCorpusMeasuredTests` (~72s) — 5
  → 2 bothPass + 2 defaultFails + 1 architectural-coverage-pending; discover
  promotes Library + Playlist to `(Verified)`, suppresses Catalog + Gallery,
  keeps Note at `(Possible)`.
- `swiftlint` clean.

## What's next

All five families' verify corpora have now been widened beyond their initial
demonstration (conservation 4, cardinality 5, biconditional 5, refint 5,
idempotence already broad). Remaining items unchanged and off the critical
path: idempotence-tca corpus widening (volume), the shelved value-generator
(c119) / `.tca` C1 (c126) items. The frozen 50.5% measured-execution rate
stays a discovery-corpus metric.
