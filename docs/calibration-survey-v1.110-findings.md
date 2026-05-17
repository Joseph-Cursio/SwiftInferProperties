# v1.110 Proactive Detector Self-Survey — Findings

Captured: 2026-05-17. swift-infer at v1.110 / SwiftPropertyLaws at v2.5.0.

## TL;DR

**Clean.** All four passes of the cycle-102 self-survey methodology, re-run against v1.110 raw outputs, surfaced zero new false positives. Cycle-102 baseline (70 occurrences / 51 unique identities) holds exactly; Finding D's 3+-slot Cardinality-overlap suppression rule is intact; Finding F (cycle-103 ReducerCandidate dedupe) had no calibration-corpus impact, as predicted. Detector-fix queue genuinely empty at v1.110 — confirms my earlier "cycle 104 is the realistic next step" call.

No code changes. No version bump. No new findings to queue beyond the still-deferred Finding E (cycle 102, Conservation Cartesian-product over aggregates × collections — corpus has only 1×1=1 case, no false positive surfaces).

## Methodology

Re-applied the four-pass survey from `docs/calibration-cycle-102-findings.md §"Self-survey methodology"` against v1.110 raw outputs (regenerated this cycle, persisted at `docs/calibration-survey-v1.110-data/`):

1. **Pass 1 — unique predicate dump per family** — look for pattern outliers (the cycle-100 triplicate `state.alert + state.alert + state.alert` was visible from this pass).
2. **Pass 2 — per-reducer witness counts per family** — Cartesian-product hotspots.
3. **Pass 3 — cross-family overlap** — same fields firing in multiple families (cycle-102 Finding D shape).
4. **Pass 4 — within-corpus duplicates** — same-identity-hash duplicates from cross-file aggregation (cycle-100 Finding A shape).

## Re-measurement at v1.110

| Corpus | Cycle-102 | Cycle-survey | Δ |
|---|---:|---:|---:|
| HandRolled | 15 | 15 | 0 |
| TCA 1.25.5 (7 targets) | 31 | 31 | 0 |
| TCA 1.0.0 (3 targets) | 24 | 24 | 0 |
| **Total occurrences** | **70** | **70** | **0** |
| **Unique identities (cross-corpus dedup)** | **51** | **51** | **0** |

Per-family:

| Family | Cycle-102 | Cycle-survey | Δ |
|---|---:|---:|---:|
| Idempotence | 55 | 55 | 0 |
| Biconditional | 8 | 8 | 0 |
| Cardinality | 5 | 5 | 0 |
| Referential Integrity | 1 | 1 | 0 |
| Conservation | 1 | 1 | 0 |

Detection-neutral across v1.107 (Finding F) + v1.108 (bridge triage namespace) + v1.109 (`--interactive-bridges` flag) + v1.110 (accept-bridge recorder + pipeline refactor), as predicted by each cycle's ship comment.

## Per-pass results

### Pass 1 — unique predicate dump per family

| Family | Occurrences | Unique predicates |
|---|---:|---:|
| Idempotence | 55 | 20 |
| Biconditional | 8 | 4 |
| Cardinality | 5 | 4 |
| Conservation | 1 | 1 |
| Referential Integrity | 1 | 1 |

All 20 idempotence predicates map cleanly to `IdempotenceWitnessDetector.exactNames` (`refresh / reset / clear / dismiss / cancel / close / hide / select / task / delegate / binding`) or `namePrefixes` (`set / select / show / present`). All 4 biconditional predicates (`isLoading == (fact != nil)`, `isLoadingResults == (activeTask != nil)`, `isLoadingResults == (cachedResult != nil)`, `isNavigationActive == (optionalCounter != nil)`) are semantically well-formed; the `isLoadingResults × cachedResult` semantic noise case is the same one cycle-102 flagged as rubric-handled. All 4 cardinality predicates well-formed (2-slot + 2-slot + 2-slot + 3-slot Hand03). No structural malformation.

### Pass 2 — per-reducer witness counts per family

14 reducers fire ≥ 2 same-family witnesses. Largest hotspots:

- `MultipleDestinations.body` (6 idempotence) — 3 distinct `.show*` actions × 2 corpus versions
- `SettingsReducer.reduce` (4 idempotence) — 4 distinct independent action cases
- `NavigateAndLoad.body` (4 idempotence) — 2 distinct actions × 2 corpus versions
- ... (10 more, same shape)

All explained as either (a) cross-corpus duplicates from the TCA 1.0.0 ↔ 1.25.5 pinning paying off, or (b) within-corpus distinct action cases on the same reducer. No Cartesian-product malformation.

### Pass 3 — cross-family overlap

5 reducers fire in ≥ 2 families:

| Reducer | Families | Verdict |
|---|---|---|
| `PresentationReducer.reduce` | cardinality, idempotence | State-shape × action-shape orthogonal. **Finding D rule holds**: 3-slot Cardinality witness on `(isShowingSheet, isShowingAlert, activeFullScreenCover)` correctly suppressed bicond cross-pairings — zero bicond entries on this reducer. |
| `reduce` (Hand06 elm) | cardinality, idempotence | Orthogonal — Cardinality on state fields, Idempotence on `.refresh` action. |
| `MessageListReducer.reduce` | idempotence, referential-integrity | Independent invariants on the same reducer; `.select` action vs `selectedMessageID × messages` state. Rubric handles the `.select` triage. |
| `NavigateAndLoad.body` | biconditional, idempotence | Orthogonal — Bicond on state, Idempotence on action. |
| `EagerNavigation.body` | biconditional, idempotence | Same shape as NavigateAndLoad. |

No new Finding-D-shape regression. The cycle-102 fix's 3+-slot threshold was the right cut.

### Pass 4 — within-corpus duplicates

**Zero within-corpus duplicates** at v1.110. Finding A (cycle 100, distinct-field dedupe) is intact.

Cross-corpus duplicates (TCA 1.0.0 + TCA 1.25.5 share identical reducer/family/predicate identities): 19 (matches the cycle-104 scaffold's predicted denominator of 70 → 51 via cross-corpus collapse).

## Findings queue after this survey

**No change.** Detector-fix queue stays empty. Finding E remains queued (not actionable until corpus exhibits multi-collection Conservation pattern).

## What this confirms about cycle 104

The cycle-104 scaffold's denominator (70 / 51) is verified accurate at v1.110. The triage worksheet rows in `docs/calibration-cycle-104-findings.md` are the right input set. When the human triage cycle runs, it can proceed against this corpus state without re-baselining.

## Raw outputs

11 files at `docs/calibration-survey-v1.110-data/` — one per `<corpus>-<target>` combination, plus a `_records.json` flat table used by all four passes.
