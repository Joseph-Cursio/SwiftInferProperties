# v1.102 Calibration Cycle 99 — Findings (metrics-interaction aggregation helper)

Captured: 2026-05-17. swift-infer at v1.102 / SwiftPropertyLaws at v2.5.0.

## Headline

**Cycle 99 scaffolds the calibration-loop aggregation helper before the first datapoint cycle.** New `swift-infer metrics-interaction` subcommand reads one or more `.swiftinfer/interaction-decisions.json` files (per-corpus, walk-up default or explicit `--decisions <path>` repeatable), aggregates per-family + overall acceptance rates, renders to markdown or plain-text. Markdown output is suitable for direct paste into the next cycles' findings docs; plain output for terminal reading.

**No detection delta** — cycle-7 baseline (92 reducers, 76 interactions) carries forward unchanged. Helper ships ahead of the first triage cycle so that cycle 100's findings can drop the rendered metrics table in place rather than hand-counting.

## What landed

### Core (`SwiftInferCore`)

- **`InteractionDecisions.merge(_:)`** — identity-keyed fold over two decision logs, latest-timestamp-wins (mirrors v1's `Decisions.merge(_:)`). Enables multi-corpus aggregation.
- **`InteractionDecisionsAggregator`** — pure aggregation namespace. `Bucket` (per-family or overall counts + `acceptanceRate` / `skipRate` computed properties); `Report` (per-family + overall buckets); `aggregate(_:)` (entry point). Acceptance rate excludes `skipped` from the denominator per the rubric; rate returns `nil` (renders as `—`) when no records hit the denominator — avoids false 0% reports for families with no decisions yet.
- **`InteractionMetricsRenderer`** — markdown / plain-text renderer. Fixed family display order (idem / bicon / card / refint / cons) matches the cycle-N findings per-family-distribution table for at-a-glance comparison. Skip rate beyond a configurable threshold (default 30%, the rubric's refinement threshold) gets a trailing `*` and a footnote, so the reader can spot rubric-gap candidates immediately.

### CLI (`SwiftInferCLI`)

- **`swift-infer metrics-interaction`** subcommand. Two modes mirror v1's `metrics`:
  - **Default** (no args): walk up from `--directory` or CWD to `Package.swift`, read `<root>/.swiftinfer/interaction-decisions.json`. Single-corpus.
  - **Aggregation**: ≥ 1 repeatable `--decisions <path>` flag. Each file loaded explicitly, merged via `InteractionDecisions.merge(_:)`, rendered.
- `--format markdown|plain` toggle, default markdown.
- Warnings (missing file, malformed JSON, newer schemaVersion) flushed to stderr via the existing `InteractionDecisionsLoader.Result.warnings` channel.

### Tests

- **`InteractionDecisionsAggregatorTests`** — 7 tests covering empty / per-family / overall / accept-arm-collapsing / skip exclusion / nil-rate-on-no-decisions / merge-latest-wins.
- **`InteractionMetricsRendererTests`** — 6 tests covering markdown headers / acceptance-rate percent / empty-render-dashes / skip-threshold-asterisk-and-footnote / plain-format-fixed-width / empty-sources-sentinel.
- 14 new tests total. Test count carries through to cycle-99.

End-to-end smoke (4-record synthetic JSON): per-family table renders correctly in both modes; skip-rate flagging fires on `>30%` per family with the footnote appended.

## Why ship this in cycle 99, not cycle 100

The original cycle-98 framing positioned cycle 99 as the first triage-datapoint cycle. The user pivoted to "scaffold the cycle-99 aggregation helper" — ship the tooling first so the actual triage cycles can drop the rendered metrics table directly into their findings rather than hand-aggregating. Cleaner workflow:

| Cycle | What lands |
|---|---|
| 98 | Methodology (rubric) + baseline confirmation |
| 99 | **Aggregation helper** (this cycle) |
| 100 | First per-family acceptance rate datapoint (triage + helper-rendered table) |
| 101 | Second datapoint |
| 102 | Third datapoint; families at ≥ 70% across 100–102 propose tier promotion in cycle-102 findings |

## What's still in flight after v1.102

- **Cycles 100 / 101 / 102** — the three triage-datapoint cycles. Human-in-loop dependency.
- **Bridge-level N-arm peer triage** (PRD §9.4 full form, queued from cycle-95) — lower priority than the calibration loop.
- **Real-world TCA dogfooding** on a non-corpus project — surfaces cross-cutting ergonomics that synthetic corpora don't.

## Notes on the API shape

The aggregator is intentionally separate from the renderer (the same `Report` could feed a JSON sink later if the calibration loop ever needs machine-readable rate history — out of scope for v2.0). The renderer is intentionally separate from the CLI command (the same renderer can be called from `metrics-interaction` or from a future Swift script that aggregates across multiple cycles' decision snapshots).

The 30% skip-rate threshold is configurable in `InteractionMetricsRenderer.render(..., skipRateThreshold:)` rather than baked in — the rubric chose 30% as the refinement threshold but the rendering helper doesn't constrain that choice.
