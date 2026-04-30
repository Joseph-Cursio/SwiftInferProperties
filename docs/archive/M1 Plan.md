# M1 Execution Plan

Working doc for the M1 milestone defined in `SwiftInferProperties PRD v0.3.md` §5.8. Decomposes M1 into seven sub-milestones so progress is checkable session-by-session. **Ephemeral** — archive or delete once M1 ships and §19 success criteria are met.

## Sub-milestone breakdown

| Sub | Scope | Why this order |
|---|---|---|
| **M1.1** | Scaffolding: add `swift-infer` executable target, `swift-argument-parser` dep, `discover` subcommand stub that prints "no suggestions yet" | Establishes the CLI surface and target layout (`SwiftInferCore` / `SwiftInferTemplates` / `SwiftInferCLI`) before any behavior |
| **M1.2** | SwiftSyntax pipeline → `[FunctionSummary]` records with type-flow lite (composition detection, non-deterministic API call detection — feeds §4.1's new -∞ row) | Pure parsing; no matching, no scoring. Forces the data model to settle |
| **M1.3** | Idempotence template end-to-end: signals → §4 scoring → §4.5 explainability block rendering | Simplest template (single-function); flushes out the scoring + rendering plumbing |
| **M1.4** | Cross-function pairing (type → naming → scope filter) + round-trip template | Builds on M1.3's plumbing; pairing is the only new concept |
| **M1.5** | `// swiftinfer: skip [hash]` marker suppression + suggestion-identity hash (§7.5) | Hash needs round-trip + idempotence shipped first to test against |
| **M1.6** | Perf integration tests against `swift-collections` + `swift-algorithms` (< 2s wall on 50-file module per §13) | Validation, not new code |
| **M1.7** | §16 hard-guarantee integration tests (no source modification, no network, byte-identical reproducibility under fixed seed) | Validation, not new code |

## M1 acceptance bar (from PRD §5.8)

M1 is not done until:

a. Every emitted stub for round-trip and idempotence has a golden-file test (per §18) covering the explainability block byte-for-byte.
b. The §13 performance budget for `swift-infer discover` (< 2s wall on 50-file module) is hit on `swift-collections` and `swift-algorithms`.
c. The §16 hard guarantees relevant to discovery (no source-file modification, no telemetry, byte-identical reproducibility under fixed seeds) have integration tests in CI.

## Sampling deferred to M4

§5.8 M1 does **not** include the sampling pass — that's M4 ("sampling-before-suggesting (§4.3) using the seeded policy of §16 #6"). M1 emits the explainability block with `samplingResult: .notRun` and tier mapping still works without the +10 sampling signal.

Consequence: M1 does **not** need `DerivationStrategist` exposed publicly from SwiftProtocolLaws — that prerequisite stays at M3 per §21 OQ #4.

## New dependencies introduced in M1

- `swift-argument-parser` (M1.1) — canonical Apple-blessed CLI library; same dep SwiftPM itself uses.

## Target layout decided in M1.1

```
Sources/
  SwiftInferCore/         # data model: FunctionSummary, Suggestion, Score, ExplainabilityBlock
  SwiftInferTemplates/    # Round-Trip, Idempotence; depends on Core
  SwiftInferCLI/          # ArgumentParser-driven; `discover` subcommand; depends on Core + Templates
  swift-infer/            # executable; thin main.swift, depends on CLI
Tests/
  SwiftInferCoreTests/
  SwiftInferTemplatesTests/
  SwiftInferCLITests/
  SwiftInferIntegrationTests/  # M1.6 + M1.7 integration suites
```

The existing `SwiftInfer` library target is renamed `SwiftInferCore` in M1.1 (the public umbrella `SwiftInfer` namespace can re-export from a thin top-level target if needed for API ergonomics — decide at M1.3 once we know the public surface).
