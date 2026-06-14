# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository. **This file is a pointer-only index** — per-cycle narratives live in `git log` + `docs/calibration-cycle-N-findings.md` + `docs/calibration-cycle-N-data/`.

## What this repo is

**SwiftInferProperties** — type-directed property inference for Swift. Surfaces idempotence, round-trip pairs, and algebraic-structure (semigroup / monoid / group / semilattice / ring) candidates from function signatures, cross-function pairs, and existing unit tests. All output is human-reviewed; nothing auto-executes.

One-way downstream of [SwiftPropertyLaws](https://github.com/Joseph-Cursio/SwiftPropertyLaws):

```
SwiftInferProperties → SwiftPropertyLaws (PropertyBackend, DerivationStrategist) → swift-property-based
```

## Repository state

**Current: v1.115.0** — cycle 107, **idempotence promotion `.possible → .likely` SHIPPED** (`docs/calibration-cycle-107-findings.md`, Captured 2026-06-14). After idempotence held 100% across cycles 104+105+106, two changes landed: `IdempotenceInteractionTemplate.initialScore` 30→40 (the `.likely` band) + `InteractionTemplateFamily.makeSuggestion` now derives tier via `tierFor(family:score:)` = `Tier(score:)` clamped to `.possible` when `swiftProjectLintDeferral != nil` (the Finding-G gate keeps cardinality/biconditional pinned). **Idempotence is the first interaction family to graduate past default-`.possible`** — `discover-interaction` with no flags now surfaces idempotence at `Score: 40 (Likely)`; the other 4 families stay hidden behind `--include-possible`. Does NOT unlock M9/M10 (needs `.strong`). Suite green (3157). For the change-by-change story, read `git log` and the per-cycle findings docs.

**Current: v1.117.0 — cycle 110, Blocker B FIXED** (`docs/calibration-cycle-110-findings.md`). Interaction measured-execution now runs end-to-end **from the CLI**: `verify-interaction` on a nested-State/Action reducer returns `measured-bothPass` (1024/1024). Root cause was the toolchain's swift-testing `libTesting.dylib → Testing.framework` migration (the V1.53.A `DYLD_LIBRARY_PATH` fix became a no-op). Fix: `VerifierSubprocess` now also injects `DYLD_FRAMEWORK_PATH` (new `cachedTestingFrameworkDirectory` locator) + parser hardening so a dyld launch failure → `.measuredError`, never `.measuredDefaultFails`. New durable proof: `InteractionVerifyMeasuredExecutionTests` (real build+run, `.subprocess`). Benefits the algebraic CLI path too. Cycles 108/109 found + fixed Blocker A (nested-type qualification).

**What's next — reopen the A1 `.likely → .strong` campaign.** Measured execution runs now, but two items remain before a measured three-cycle run: **(1) interaction verify-evidence persistence** — `VerifyInteractionPipeline` still doesn't call `VerifyEvidenceRecorder` (the "M9" outcome→`verify-evidence.json`→`Tier.promoted(byVerifyOutcome:)` join), so measured outcomes can't yet promote tier; **(2) CLI corpus packaging** — the HandRolled/TCA corpora aren't standalone SwiftPM packages exposing their target as a product (note: the package-root dir must be named after the module — SwiftPM derives path-dep identity from the directory name). Then run `verify-interaction` over the 39 idempotence identities, harvest `.measuredBothPass`, and gate `.strong` on execution. **Idempotence stays `.likely`** until then.

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
- Non-subprocess fast path: `swift test --skip VerifyPipelineIntegrationTests --skip InteractionVerifyMeasuredExecutionTests` (~4s); full `swift test` is dominated by parallel subprocess builds (both suites spawn real `swift build` + verifier runs).
- SwiftLint config at `.swiftlint.yml`; `swiftlint lint --quiet` should be silent.
