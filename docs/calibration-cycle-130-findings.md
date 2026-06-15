# Calibration cycle 130 — C2 corpus widening (6 reducers / 13 identities)

> **STATUS: SHIPPED (no version bump — fixtures + durable test).** Widens the
> verify-ready real-TCA corpus from 4 → 6 reducers (10 → 13 idempotence
> identities), adding a richer multi-excluded Phase B disclosure and an
> **exact-witness false positive** (alongside the existing `set*` one).
> Cheap to add now — cycle-129's warm shared workdir makes each new reducer
> ~one incremental build, not a cold one (survey 96s for 13 identities).
> Captured 2026-06-15.

## What was added

- **`DownloadFeature`** (mixed, Phase B) — TWO non-derivable cases
  (`received(Data)`, `markItems(IndexSet)`), so the disclosure lists a
  richer excluded set: `explored 3 of 5 action types (excluded: received,
  markItems)`. `dismiss` is the payload-free witness; `updateStep(Int)` is a
  raw exploration case (assigned, overflow-safe per cycle 128).
- **`ToggleFeature`** (all-payload-free, Phase A) — `hide` is an **exact**
  idempotence witness by name whose body **toggles** (apply twice ≠ once →
  not idempotent), an exact-witness FALSE positive mirroring
  `EditorFeature.setBadge`'s `set*` false positive. `select` is a genuine
  true positive in the same reducer.

## Result

The detector now surfaces **13 idempotence identities → 11 `measured-bothPass`
+ 2 `measured-defaultFails`**. Both `defaultFails` are name-vs-behavior false
positives that static analysis proposes and execution rejects, now across
**both witness categories**: `setBadge` (`set*` prefix) and `ToggleFeature.hide`
(exact). The campaign's core value — execution disproving plausible-by-name
suggestions — is demonstrated in both directions and both categories.

Phase B disclosure coverage now spans 1- and 2-excluded sets
(`excluded: sync`, `excluded: received`, `excluded: received, markItems`);
the all-payload-free reducers (NavFeature, SelectionFeature, ToggleFeature)
carry no caveat.

## Verification

`TCAVerifyCorpusMeasuredTests` green (13 identities → 11/2; richer
`excluded: received, markItems` disclosure; mixed reducers disclose, full
reducers don't; evidence 13/11/2; discover renders `(Verified)`). ~96s —
the warm shared workdir (cycle 129) amortizes the heavy TCA build across all
13 identities. `swiftlint` clean; fast suite unaffected (subprocess-skipped).

## What's next

The corpus widens further the same way at ~one incremental per reducer. The
`.tca` epic stays complete; remaining genuinely-optional is C1's literal
discovery-corpus extractor (only if that number is ever required). Default
idempotence stays `.likely`; the other four interaction families stay
`.possible` behind `--include-possible`.
