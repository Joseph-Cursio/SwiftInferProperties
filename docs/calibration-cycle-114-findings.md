# Calibration cycle 114 — `verify-interaction --all` survey mode

> **STATUS: SHIPPED (v1.121.0).** The campaign's harvest step: one command
> discovers every interaction-invariant identity in a target, runs measured
> verify against each, records evidence, and prints a per-identity outcome
> summary — instead of N hand-pinned `verify-interaction` runs. Serial by
> design (see below). Captured 2026-06-14.

## Context

Cycle 113 finished the A1 infrastructure (package → verify → record →
consume). What remained was ergonomics: harvesting the ~39 idempotence
identities meant 39 hand-pinned `verify-interaction --reducer …` runs.
This cycle makes it one command.

## What shipped

**`verify-interaction --all` + `--family <name>`.** `--all` discovers
every interaction-invariant identity in `--target` (via
`DiscoverInteraction.collectSuggestions`), runs measured verify against
each, and renders a summary. `--family idempotence` narrows the survey to
one family (unknown values are a clean error); `--reducer` is ignored in
`--all` mode (with a stderr warning).

**`VerifyInteractionSurvey` (SwiftInferCLI).** `run(...)` orchestrates
discover → optional family filter → serial measured verify → rendered
summary. `runWithInvariant` (cycle 111) already records evidence per call,
so the survey's evidence harvest is a side effect of the loop — no
separate batch step. The renderer is pure (`render`, `parseFamily`,
`tally`), so it's unit-tested without a build.

The summary lists each identity with its outcome + detail, a
count-by-outcome tally in canonical order, and the evidence-recorded line:

```
swift-infer verify-interaction --all — V2.0 survey of 'IdempotenceCorpus'
  Identities: 2 (--family idempotence)

  [measured-bothPass]              CounterReducer.reduce  idempotence  .refresh
  [measured-bothPass]              CounterReducer.reduce  idempotence  .reset

  Summary: 2 measured-bothPass
  Evidence recorded to .swiftinfer/verify-evidence.json (2 identities).
```

## Key design decision — serial, not parallel

The algebraic `verify --all-from-index` runs a bounded-parallel
`TaskGroup`. The interaction survey is **serial**, and deliberately so: the
interaction verify workdir is keyed by **reducer**
(`workdirSegment(for: candidate)`), not per-invariant. Two idempotence
identities on the same reducer (a common shape — `refresh` + `reset`)
share that workdir, so building them concurrently would clobber. The
algebraic side gets parallelism only because its workdirs are
identity-hash-keyed.

Running serially also makes `runWithInvariant`'s per-call evidence record
race-free, so no `recordBatch` is needed. **Per-invariant workdir
isolation is the prerequisite for a parallel interaction survey** — a
noted follow-up, not this cycle.

## Verification

- **Fast (`VerifyInteractionSurveyTests`, 6):** `--all` / `--family`
  argument surface + defaults; `parseFamily` known / nil / unknown-throws;
  `render` lists identities + the count-by-outcome tally + the evidence
  line; empty-survey sentinel.
- **End-to-end (`VerifyInteractionSurveyMeasuredTests`, 1, `.subprocess`,
  ~20s):** packages a one-reducer corpus with **two** idempotence
  witnesses (`.refresh` + `.reset`) so the survey exercises the
  serial-same-workdir path; asserts `2 measured-bothPass`, two evidence
  records persisted, and that `discover-interaction` then renders both
  `(Verified)`.
- **Suites:** full fast suite green (3189 tests; only the known §13
  perf-budget timing flakes under load). SwiftLint clean.

## What's next — run the real survey

The mechanism is ready. The campaign is now:

1. **Stage a verify-ready idempotence corpus.** Package the idempotence
   identities that satisfy the verify shape (`CaseIterable` Action,
   `Equatable` / zero-arg State); the rest survey as
   `architectural-coverage-pending` (surfaced, not dropped).
2. **`verify-interaction --all --family idempotence`** over it → evidence.
3. **`discover-interaction`** surfaces survivors at `.verified`, across the
   documented three calibration cycles, gating `.strong`/`.verified` on
   execution.

Follow-up mechanisms when needed: per-invariant workdir isolation (unlocks
a parallel survey) and a `dependencies:` thread in `CorpusPackager` (for
the TCA corpora). Default (no-evidence) idempotence stays `.likely`.
