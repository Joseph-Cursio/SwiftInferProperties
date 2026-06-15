# Calibration cycle 144 — tca-verify (idempotence) corpus widened (11 → 13 reducers)

**Captured 2026-06-15.** No binary change — fixtures + test updates. Fifth
corpus-widening follow-up, and the last family corpus to widen. Unlike the
other four (which were thin), the idempotence `tca-verify-corpus` is already
broad (cycle 131/133), so per its own guidance this widening targets only
**genuinely-new shapes**: the `CombineReducers` composition operator and the
Double + Bool raw generators (the corpus had exercised only Int + String
raws).

## What shipped

`Tests/Fixtures/tca-verify-corpus/` gains two real `@Reducer`s:

- **CombineFeature** — body is `CombineReducers { Reduce { … }; Reduce { … } }`,
  the explicit composition operator (cycle 133 covered the bare two-`Reduce`
  body and `Scope`; CombineReducers was the remaining shape cycle 131 called
  out). The walker emits one candidate per inner `Reduce` (same
  qualifiedName); the cycle-133 dedup collapses them so the whole composed
  body verifies via `CombineFeature().reduce`. The payload-free `dismiss`
  witness → `measured-bothPass` (full coverage).
- **GaugeFeature** — adds `tune(Double)` and `flag(Bool)` exploration cases,
  driving the `Gen<Double>.double(…)` and `Gen<Bool>.bool()` RawType
  generators the corpus hadn't exercised (only Int + String before). Both
  are constructible → full coverage. The payload-free `reset` witness (sets
  State to defaults) → `measured-bothPass`.

## Measured baseline

`verify-interaction --all --family idempotence` now: **21 identities → 19
`measured-bothPass` + 2 `measured-defaultFails`** (the two false positives —
`EditorFeature.setBadge` and `ToggleFeature.hide` — unchanged). The two new
witnesses (`CombineFeature.dismiss`, `GaugeFeature.reset`) both verify
bothPass; both reducers are full-coverage (CombineReducers payload-free;
Gauge's Double/Bool payloads constructible).

## Verification

- **Measured (`.subprocess`):** `TCAVerifyCorpusMeasuredTests` (~162s) — 21
  → 19 bothPass + 2 defaultFails; CombineFeature + GaugeFeature added to the
  full-exploration set; the new witnesses asserted present + bothPass; the
  two false positives still suppressed.
- `swiftlint` clean.

## What's next

All five families' verify corpora have now been widened beyond their initial
demonstration (conservation 4, cardinality 5, biconditional 5, refint 5,
idempotence-tca 13). The cycle-131 widening criterion is now largely
exhausted for idempotence-tca — the distinct verify mechanisms (closure +
method-ref discovery, `.none` + effect bodies, all composition operators,
Int/String/Double/Bool raws, Phase A + B, exact + `set*` false positives,
1- & 2-excluded disclosures) are all exercised; further additions would be
pure volume. Remaining items unchanged and off the critical path: the
shelved value-generator (c119) / `.tca` C1 (c126) items. The frozen 50.5%
measured-execution rate stays a discovery-corpus metric.
