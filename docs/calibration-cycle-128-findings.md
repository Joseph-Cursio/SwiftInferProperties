# Calibration cycle 128 — C2 corpus widening (4 reducers / 10 identities)

> **STATUS: SHIPPED (no version bump — fixtures + durable test, no binary
> change).** Widens the cycle-127 verify-ready real-TCA corpus from 2 to 4
> reducers (5 → 10 idempotence identities), broadening witness-vocabulary
> coverage and adding a `set*` **true positive** to mirror the existing
> `set*` false positive. Surfaced one real calibration finding (raw-Int
> overflow during exploration). Captured 2026-06-15.

## What was added

Two more self-contained real `@Reducer` reducers in
`Tests/Fixtures/tca-verify-corpus/`:

- **`SelectionFeature`** — all-payload-free (Phase A). Broadens witness
  vocabulary: `select` (exact), `selectFirst` (`select*` prefix),
  `showDetail` (`show*` prefix). 3 `bothPass`.
- **`SettingsFeature`** — mixed (Phase B). `setEnabled` is a `set*` witness
  that is a genuine **TRUE positive** (sets a flag to a fixed value →
  idempotent), the mirror of `EditorFeature.setBadge`'s `set*` **FALSE**
  positive — execution distinguishes them. Plus `cancel` (exact witness),
  `adjust(Int)` (raw exploration, non-witness), `sync(Data)` (non-derivable,
  excluded). 2 `bothPass`, disclosure `excluded: sync`.

## Result

The real witness detector now surfaces **10 idempotence identities → 9
`measured-bothPass` + 1 `measured-defaultFails`** (`setBadge`). Witness
vocabulary exercised end-to-end: exact `dismiss`/`close`/`hide`/`select`/
`cancel`, prefixes `select*`/`show*`/`set*`. The mixed reducers
(EditorFeature, SettingsFeature) carry the Phase B partial-exploration
disclosure; the all-payload-free ones (NavFeature, SelectionFeature) don't.

## Calibration finding — raw-Int overflow traps the whole reducer

The first draft of `SettingsFeature` had `case adjust(Int)` doing
`state.volume += delta`. Result: **all** SettingsFeature witnesses
(`setEnabled`, `cancel`) came back `measured-defaultFails`, not just the
intended set. Cause: the raw-Int generator (`Gen<Int>.int()`) draws
full-range values, so `volume += delta` overflow-**traps** during the
*exploration* phase — and a trap in exploration fails every witness on that
reducer (the witness double-apply never runs).

This is the verifier behaving **correctly** — the reducer genuinely traps on
overflow — but it's a property of the *exploration driver*, not the witness,
so it masks the witness verdict. Two implications:

1. **For curated corpora:** keep raw-payload exploration cases overflow-safe
   (assignment, not accumulation) unless overflow *is* the behavior under
   test. Fixed here: `adjust` now assigns (`state.volume = value`).
2. **Real-corpus note (informs any future Phase C/C1):** a reducer with
   unbounded raw arithmetic will survey as `measured-defaultFails` for *all*
   its witnesses under relaxed exploration. That's a true (if blunt) signal —
   the reducer can trap — but worth recognizing when reading survey results:
   a reducer-wide defaultFails cluster often means an exploration-driver
   trap, not a witness-specific idempotence violation.

## Verification

`TCAVerifyCorpusMeasuredTests` green (10 identities → 9 `bothPass` + 1
`defaultFails`; `setEnabled` true positive vs `setBadge` false positive;
mixed reducers disclose excluded cases, full reducers don't; evidence
10/9/1; discover renders `(Verified)`). `swiftlint` clean. The suite stays
`.subprocess` (resolves TCA; ~200s now — four reducers, each witness a real
build) and is already on the fast-path skip list.

## What's next

The `.tca` epic stays **complete for practical purposes**; the corpus can be
widened further the same way. Off the critical path: the shared prebuilt
user-package artifact (cycle 120 perf tail) — increasingly relevant as this
suite grows (~200s); C1's literal discovery-corpus extractor (only if that
number is ever required). Default idempotence stays `.likely`; the other
four interaction families stay `.possible` behind `--include-possible`.
