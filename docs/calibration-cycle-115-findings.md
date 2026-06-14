# Calibration cycle 115 — verify-ready idempotence corpus + first measured baseline

> **STATUS: SHIPPED (v1.122.0).** Stages a checked-in, verify-ready
> idempotence corpus and runs the first *measured* idempotence survey over
> it. Result: **8 identities → 7 `measured-bothPass` (promoted to
> `.verified`) + 1 `measured-defaultFails`** — the deliberate `set*` false
> positive that static analysis can't rule out but execution disproves.
> Promotion gated on execution, end-to-end, on representative data.
> Captured 2026-06-14.

## Context

Every A1 mechanism shipped (cycles 110–114): measured execution, the
verify-evidence producer + consumer, corpus packaging, and the `--all`
survey. What was missing was *data* — a verify-ready corpus to actually
run the survey against. Cycle 113 established why the real discovery
corpora can't be surveyed as-is: the verify stub needs a `CaseIterable`
Action (all cases payload-free) + an `Equatable`, zero-arg-constructible
`State`, and most corpus reducers carry associated-value Actions
(`setColor(String)`, `showCover(String)`, `select(Message.ID?)`) that can't
conform.

This cycle stages a curated corpus that *is* verify-ready, and harvests
the first real measured numbers.

## What shipped

**A checked-in verify-ready idempotence corpus** —
`Tests/Fixtures/idempotence-survey-corpus/` (3 reducers, packaged at test
time via `CorpusPackager.fromSourcesDirectory`). It covers the witness
vocabulary breadth:

- `NavigationReducer` — `dismiss`, `close`, `hide` (exact-match witnesses),
  each clearing a presentation flag → idempotent.
- `SelectionReducer` — `select` (exact), `selectFirst` (prefix `select*`),
  `showDetail` (prefix `show*`), each driving state to a fixed point.
- `SettingsReducer` — `cancel` (exact, genuinely idempotent) **plus the
  load-bearing false positive `setBadge`**: it matches the `set*` witness
  prefix (the name reads "set to a fixed value"), so the static detector
  emits an idempotence suggestion — but the body *increments* a counter, so
  applying twice ≠ once. Static analysis can't distinguish a fixed-value
  setter from an accumulating one; only execution can.

All actions are payload-free (so `Action: CaseIterable`), States are
`Equatable` with zero-arg inits, and the driver cases (`present`,
`advance`, `tick`) deliberately avoid the witness vocabulary.

## The first measured idempotence baseline

`verify-interaction --all --family idempotence` over the packaged corpus:

| Outcome | Count | Identities |
|---|---|---|
| `measured-bothPass` | **7** | dismiss, close, hide, select, selectFirst, showDetail, cancel |
| `measured-defaultFails` | **1** | `SettingsReducer.setBadge` (the deliberate false positive) |

`discover-interaction` then reads the harvested evidence and renders the 7
survivors at `.verified`; `setBadge` is suppressed (absent from the
stream). **This is the campaign thesis demonstrated on data:** promotion is
gated on execution, and execution caught a name-based suggestion the static
detector could not rule out.

## Verification

- **Fast (`IdempotenceSurveyCorpusTests`, 1):** packaging + discovery
  surfaces *exactly* the 8 intended identities (an equality assertion on
  the identity set — locks the corpus shape and confirms the driver cases
  produce no spurious witnesses); all sit at `.likely` pre-survey.
- **Measured (`IdempotenceSurveyCorpusMeasuredTests`, 1, `.subprocess`,
  ~66s):** the survey records the 7/1 split, persists 8 evidence records,
  and `discover-interaction` promotes only the survivors (`(Verified)`
  present, `.setBadge` absent, no `(Likely)` remaining).
- **Suites:** full fast suite green (3191 tests; only the known §13
  perf-budget timing flakes under load). SwiftLint clean.

## What's next — widen the corpus, then the three-cycle promotion run

The baseline exists and the loop is proven on data. Remaining:

1. **Widen the corpus toward the real ~39 identities.** Add reducers
   mirroring more real-world idempotence shapes (TCA `task` / `delegate` /
   `binding` conventions; Elm-style free functions). The associated-value
   cases stay out of scope until a value-generator path exists — log them
   `architectural-coverage-pending` rather than dropping.
2. **The three-cycle `.likely → .strong/.verified` run.** With measured
   evidence now driving the tier, run discover over the corpus across the
   documented three calibration cycles and confirm the promotion holds —
   the empirical sign-off A1 was built to produce.

Follow-up mechanisms when needed: per-invariant workdir isolation (a
*parallel* survey) and a `CorpusPackager` `dependencies:` thread (to reach
the dependency-bearing TCA corpora). Default (no-evidence) idempotence
stays `.likely`.
