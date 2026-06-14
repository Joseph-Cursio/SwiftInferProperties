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

**Current: v1.121.0 — cycle 114, `verify-interaction --all` survey mode SHIPPED** (`docs/calibration-cycle-114-findings.md`). The campaign harvest step: `--all` discovers every interaction-invariant identity in `--target` (via `DiscoverInteraction.collectSuggestions`), runs measured verify against each, records evidence (per-call via cycle-111's `runWithInvariant`), and prints a per-identity outcome summary + count-by-outcome tally. `--family <name>` narrows to one family (unknown → clean error); `--reducer` ignored in `--all` (stderr warning). New `VerifyInteractionSurvey` (SwiftInferCLI) with a pure renderer (`render`/`parseFamily`/`tally`, unit-tested). **Serial by design** — the interaction verify workdir is reducer-keyed (`workdirSegment(for: candidate)`), so two identities on the same reducer (e.g. `refresh`+`reset`) share it and can't build concurrently; per-invariant workdir isolation (the prereq for parallelism) is a follow-up. Serial also makes the per-call evidence record race-free (no batch). Proof: `VerifyInteractionSurveyTests` (6 fast) + `VerifyInteractionSurveyMeasuredTests` (`.subprocess`, ~20s: two witnesses on one reducer → 2 bothPass → 2 evidence records → discover shows both Verified). Suite green (3189).

**Prior — v1.120.0, cycle 113, CLI corpus packaging — the A1 loop closes end-to-end** (`docs/calibration-cycle-113-findings.md`). New `CorpusPackager` (SwiftInferCLI) wraps loose reducer sources into a standalone, **module-named** SwiftPM package exposing a `library` product, so `verify-interaction` (which references the corpus as a path dependency and builds it) can run a measured survey. `package(moduleName:sourceFiles:into:)` + a `fromSourcesDirectory:` convenience (top-level `.swift` only; skips asset/plist dirs). Capstone: `IdempotenceCorpusMeasuredTests` (`.subprocess`, ~20s) drives the **full loop** over a packaged corpus — package → discover (`.likely`) → verify (`measured-bothPass`) → evidence → discover (`.verified`) — exercising cycles 110+111+112+113 together. Finding: packaging is necessary but not sufficient — the verify stub needs `CaseIterable` Action + `Equatable`/zero-arg `State`, which most existing corpus reducers don't satisfy (hence measured-exec at 50.5%); a verify-ready source shape is part of the survey. Suite green (3182). Cycle 112 closed the M9 join (verify-evidence consumer).

**Prior — v1.119.0, cycle 112, interaction verify-evidence consumer (the M9 join)** (`docs/calibration-cycle-112-findings.md`). The `discover-interaction` render path now **reads** the `verify-evidence.json` the cycle-111 producer writes and folds each outcome into the grade via new `InteractionVerifyEvidenceScoring.applied(to:evidenceByIdentity:)` (Core). `.measuredBothPass` → `score + verifyBothPassWeight` (+50, the **shared** algebraic constant), tier recomputed through the Finding-G gate, then `Tier.promoted(byVerifyOutcome:)` → idempotence `.likely` (40) becomes `.verified` (90). `.measuredDefaultFails` → `.suppressed`. The Finding-G gate moved to a single source of truth — new public `InteractionInvariantFamily.tier(forScore:)` (Core); `InteractionTemplateFamily.tierFor` now delegates to it and the fold calls it too, so cardinality/biconditional stay pinned at `.possible` even on a measured bothPass (score rises to 80, tier gated). Wired via `gradedByVerifyEvidence(...)` on the render path only (`run`/`runPipeline`), **not** `collectSuggestions` (shared with drift-interaction's baseline, which keeps the pre-verify tier). Proof: `InteractionVerifyEvidenceScoringTests` (8, Core) + `DiscoverInteractionVerifyEvidenceTests` (3, real-disk load→fold→render). Producer→consumer chain now end-to-end. Suite green (3178).

**What's next — run the real measured survey.** Every A1 mechanism now exists: package (`CorpusPackager`), survey (`verify-interaction --all`), record (verify-evidence producer), consume (`.likely → .verified`). The remaining work is *running it on real corpus data*, not building tools: **(1)** stage a verify-ready idempotence corpus — package the identities that satisfy the verify shape (`CaseIterable` Action, `Equatable`/zero-arg State); the rest survey as `architectural-coverage-pending` (surfaced, not dropped); **(2)** `verify-interaction --all --family idempotence` over it → harvest evidence; **(3)** `discover-interaction` promotes survivors to `.verified` across the documented three calibration cycles, gating `.strong`/`.verified` on execution. Follow-up mechanisms when needed: per-invariant workdir isolation (unlocks a *parallel* survey — today's is serial) and a `dependencies:` thread in `CorpusPackager` (for the TCA corpora). Default (no-evidence) idempotence stays `.likely`.

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
- Non-subprocess fast path: `swift test --skip VerifyPipelineIntegrationTests --skip InteractionVerifyMeasuredExecutionTests --skip IdempotenceCorpusMeasuredTests --skip VerifyInteractionSurveyMeasuredTests` (~4s); full `swift test` is dominated by parallel subprocess builds (these suites spawn real `swift build` + verifier runs).
- SwiftLint config at `.swiftlint.yml`; `swiftlint lint --quiet` should be silent.
