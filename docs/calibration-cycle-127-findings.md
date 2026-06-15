# Calibration cycle 127 — Phase C / C2 SHIPPED (verify-ready real-TCA corpus)

> **STATUS: SHIPPED (no version bump — fixtures + durable test, no binary
> change).** Implements the cycle-126 recommendation (C2): a checked-in,
> verify-ready corpus of **real `@Reducer` + `@ObservableState`** reducers
> that the measured `--all` survey verifies end-to-end through the **real
> witness detector** + the Phase A/B `.tca` path. No reducer-slice extractor
> (C1 avoided). Captured 2026-06-15.

## What shipped

- **`Tests/Fixtures/tca-verify-corpus/`** — two self-contained real-TCA
  reducers (no Views / cross-file refs / UIKit, all-defaulted `Equatable`
  `@ObservableState`):
  - **`NavFeature`** — all-payload-free Action (`present` driver +
    `dismiss`/`close`/`hide` idempotent witnesses) → Phase A full
    exploration.
  - **`EditorFeature`** — a MIXED Action: `close` (payload-free idempotent
    witness), `setBadge` (a deliberate `set*` FALSE POSITIVE — reads "set to
    a value" but increments), `typed(String)` (raw-payload exploration),
    `received(Data)` (non-derivable, excluded), `beginEditing` (driver) →
    Phase B relaxed partial exploration.
- **`TCAVerifyCorpusMeasuredTests`** (`.subprocess`, ~105s) — packages the
  corpus and runs `VerifyInteractionSurvey.run(--all --family idempotence)`.

## The measured result (real detector, real verify)

The real witness detector surfaced **5 idempotence identities** across the
two reducers, and measured verify split them:

```
Identities: 5 (--family idempotence)
  [measured-bothPass]      NavFeature.body     .dismiss
  [measured-bothPass]      NavFeature.body     .close
  [measured-bothPass]      NavFeature.body     .hide
  [measured-bothPass]      EditorFeature.body  .close   | partial exploration: explored 4 of 5 action types (excluded: received)
  [measured-defaultFails]  EditorFeature.body  .setBadge | partial exploration: explored 4 of 5 action types (excluded: received)
  Summary: 4 measured-bothPass, 1 measured-defaultFails
```

Everything the epic built is exercised together, on real `@Reducer` shapes,
via the actual survey (not hand-built invariants):

- **Phase A** — NavFeature's all-payload-free witnesses verify with full
  exploration (no caveat).
- **Phase B** — EditorFeature's verdicts carry the partial-exploration
  disclosure (`excluded: received`), the binding guardrail #1.
- **Precision** — the `setBadge` false positive is disproven by execution
  (`measured-defaultFails`), exactly the value the campaign is built on:
  static name-matching proposes it, execution rejects it.
- **The M9 join** — evidence is harvested for all 5; `discover-interaction`
  reads it back and renders the 4 survivors `(Verified)`.

## Why C2, not C1 (recap)

Cycle 126 proved the discovery corpora don't compile (AST-only: App/`@main`,
9 UIKit files, cross-file View refs even in the simplest reducer). C1 would
need a fragile reducer-slice extractor to retrofit them. C2 sidesteps that
entirely: curate self-contained reducers that compile, and the *already
shipped* Phase A/B path verifies them. The cost was corpus authoring, not
new engineering — matching the cycle-126 recommendation.

## Verification

- `TCAVerifyCorpusMeasuredTests` green (5 identities → 4 bothPass + 1
  defaultFails; EditorFeature verdicts disclose the excluded case, NavFeature
  verdicts don't; evidence count 5/4/1; discover renders `(Verified)`).
- Fast suite green (3204; the 2 observed failures were perf-budget timing
  flakes under full-suite load — non-perf filter clean — per the documented
  flake history, not regressions). `swiftlint` clean on the new files.
- Added to the fast-path skip list (`.subprocess`, resolves TCA).

## What's next

The `.tca` epic is **complete for practical purposes**: Phase A + B shipped
(real reducers, mixed Actions) and C2 demonstrates + regression-guards the
whole path on real `@Reducer` shapes. The corpus can be widened with more
curated reducers as desired. Remaining optional, off the critical path: the
shared prebuilt user-package artifact (cycle 120 perf tail); C1's literal
discovery-corpus extractor (only if that specific number is ever required).
Default idempotence stays `.likely`; the other four interaction families
stay `.possible` behind `--include-possible`.
