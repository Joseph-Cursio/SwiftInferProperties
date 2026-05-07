# v1.4 Calibration Cycle 1 — Empirical Data

Captured: 2026-05-07. swift-infer v1.4.0-pre at commit `20562bf`.

## Corpora

| Corpus | Target | Discover output | Decisions (post-triage) |
|---|---|---|---|
| swift-collections | OrderedCollections | [`swift-collections-OrderedCollections.discover.txt`](swift-collections-OrderedCollections.discover.txt) | `swift-collections-OrderedCollections.decisions.json` (V1.4.2 produces) |
| swift-numerics | ComplexModule | [`swift-numerics-ComplexModule.discover.txt`](swift-numerics-ComplexModule.discover.txt) | `swift-numerics-ComplexModule.decisions.json` |
| swift-algorithms | Algorithms | [`swift-algorithms-Algorithms.discover.txt`](swift-algorithms-Algorithms.discover.txt) | `swift-algorithms-Algorithms.decisions.json` |
| SwiftPropertyLaws | PropertyLawKit | [`SwiftPropertyLaws-PropertyLawKit.discover.txt`](SwiftPropertyLaws-PropertyLawKit.discover.txt) | `SwiftPropertyLaws-PropertyLawKit.decisions.json` |

The four `.discover.txt` files capture `swift-infer discover --target <target> --include-possible` output for each corpus at the v1.4.0-pre commit. They form the cycle-1 baseline so cycle 2 can diff "what changed in v1.4-tuned discover output" before re-triaging.

## Aggregate surface stats (across all 4 corpora, `--include-possible`)

| Template          | Total | Default-tier visible | Possible-tier (hidden) | Score |
|-------------------|------:|---------------------:|-----------------------:|------:|
| round-trip        |   990 |                    0 |                    990 |    30 |
| idempotence       |    89 |                    0 |                     89 |    30 |
| monotonicity      |    29 |                    0 |                     29 | 25/35 |
| commutativity     |    19 |                    0 |                     19 |    30 |
| associativity     |    19 |                    0 |                     19 |    30 |
| inverse-pair      |    15 |                    0 |                     15 |    25 |
| identity-element  |     6 |                    6 |                      0 |    70 |
| **Total**         | **1167** |             **6** |              **1161** |       |

## Per-corpus default-tier breakdown

| Corpus | Default-tier visible | All templates affected |
|---|---:|---|
| swift-collections / OrderedCollections | 0 | — |
| swift-numerics / ComplexModule | 6 | identity-element ×6 |
| swift-algorithms / Algorithms | 0 | — |
| SwiftPropertyLaws / PropertyLawKit | 0 | — |

## Triage instructions

See `../calibration-cycle-1-runbook.md` (sibling file) for the per-corpus invocations and the recommended triage strategy.
