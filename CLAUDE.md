# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository. **This file is a pointer-only index** — per-cycle narratives live in `git log` + `docs/calibration-cycle-N-findings.md` + `docs/calibration-cycle-N-data/`.

## What this repo is

**SwiftInferProperties** — type-directed property inference for Swift. Surfaces idempotence, round-trip pairs, and algebraic-structure (semigroup / monoid / group / semilattice / ring) candidates from function signatures, cross-function pairs, and existing unit tests. All output is human-reviewed; nothing auto-executes.

One-way downstream of [SwiftPropertyLaws](https://github.com/Joseph-Cursio/SwiftPropertyLaws):

```
SwiftInferProperties → SwiftPropertyLaws (PropertyBackend, DerivationStrategist) → swift-property-based
```

## Repository state

**Current: v1.112.0** — cycle 104, the **first triage datapoint** of the v2.0 calibration loop (`docs/calibration-cycle-104-findings.md`, Captured 2026-06-13). 51 unique identities triaged: **idempotence 100%** (sole promotion-track family, counter 1/3); **cardinality 50% + biconditional 33%** re-homed as shipped SwiftProjectLint refactor lints per **Finding G** (`mutually-exclusive-presentation-state`, `flag-optional-pair-state`); overall 89.8% (44/49). Falsified the scaffold's assumption that all 15 HandRolled anchors accept — 3 reject (fixtures are designed to be *detected*, not to *dynamically satisfy*). For the change-by-change story, read `git log` and the per-cycle findings docs.

**What's next: cycle 105** — second triage datapoint; only needs to re-confirm idempotence ≥ 70% (105 + 106 hold → `.possible → .likely` promotion proposed in cycle-106 findings). Open SInferP-side item from Finding G: re-frame cardinality/biconditional *output* to defer to the SwiftProjectLint rules (or gate behind `--include-possible`, never promote past `.possible`).

**Calibration baseline (cycle 7, holds at v1.110):** 92 reducers, 76 interactions across 11 corpus targets. Per-family: 55 idem / 10 bicon / 8 card / 2 refint / 1 cons.

**Measured-execution (v1):** 52/103 = 50.5%, frozen since cycle 66.

## Kit-side coordination

`Package.swift` pins **SwiftPropertyLaws** at `from: "2.5.0"`. Verify pipeline uses the opt-in `PropertyLawComplex` product; main `PropertyLawKit` line keeps a zero `swift-numerics` footprint. Deferred kit-side: `Ring` (Numeric stays canonical per PRD §5.4 row 5), `CommutativeGroup`, `Group acting on T`.

## Where to look

| Question | File |
|---|---|
| Product scope, milestones, success criteria | `docs/SwiftInferProperties PRD v1.0.md` (canonical) |
| Per-cycle change story | `git log` + `docs/calibration-cycle-N-findings.md` |
| Calibration corpus + baseline | `docs/calibration-corpus-v2.0.md` |
| Triage rubrics | `docs/interaction-invariant-triage-rubric.md` (v2.0) + `docs/cycle-6-triage-rubric.md` (v1) |
| Perf baseline | `docs/perf-baseline-v1.63.md` — last in series; not updated in v2.0 (was tied to the v1.42–v1.63 verify-pipeline arc) |
| Closed milestone + calibration plans | `docs/archive/*.md` |
| PropertyLawKit / PropertyLawMacro source of truth | The SwiftPropertyLaws repo, not this one |

## Design decisions baked in (follow rather than re-litigate)

- **Conservative inference — high precision, low recall.** PRD §3.5. When in doubt, fewer suggestions.
- **Opt-in, human-reviewed output.** Never auto-applies/executes/commits. CI mode emits warnings, not failures.
- **Avoid the Daikon trap.** Too many suggestions → raise thresholds, don't pile on filters.
- **Explainability is a first-class output.** Every suggestion ships "why suggested" + "why this might be wrong." PRD §4.5.
- **Generator inference delegates to SwiftPropertyLaws.** Call `DerivationStrategist`; don't reimplement. PRD §11.

## Build & test

- `swift package clean && swift test` (per global `~/CLAUDE.md`) on session start.
- Skeleton expects `../SwiftPropertyLaws` as a sibling checkout. CI checks both repos out side-by-side.
- Non-subprocess fast path: `swift test --skip VerifyPipelineIntegrationTests` (~4s); full `swift test` is dominated by parallel subprocess builds.
- SwiftLint config at `.swiftlint.yml`; `swiftlint lint --quiet` should be silent.
