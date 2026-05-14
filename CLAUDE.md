# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**Current: v1.70.0** — sixty-seventh calibration cycle; **roadmap cleanup — the last two open items close** (not a measurement cycle). V1.70.A `metrics --decisions` aggregation mode now joins each corpus's sibling `verify-evidence.json` into the §17.2 cross-reference (new `VerifyEvidenceLog.merge`, mirroring `Decisions.merge`) — V1.64.D's cross-reference was previously default-walk-up-mode-only. V1.70.B closes **V1.42.C.5** (deferred 27 cycles): `swift-infer verify` reindexes the SemanticIndex on demand when the conventional `.swiftinfer/index.json` is missing or stale, via the new callable static `Index.performIndex` + `Verify.reindexIfNeeded` (whole-`Sources/` scan; an explicit `--index-path` is used as-is; a package with no `Sources/` is left alone). **Test count 2498 → 2512 (+14). The documented roadmap is now empty.**

**Measured-execution: 52/103 = 50.5%** — 38 `.bothPass` + 6 `.defaultFails` + 8 `.edgeCaseAdvisory` + 0 `.measured-error` + 51 `.architectural-coverage-pending` (carried from cycle 66 — v1.70 touches no emitter/resolver/carrier path). The committed `fixtures/cycle27-surface/.swiftinfer/verify-evidence.json` (103 records, refreshed v1.69.C) is the on-disk evidence artifact. Per-pick correctness: semantic "property holds" match 13/13 = **100%** on the cycle-46 sample subset.

**The verify-evidence arc is complete, internally consistent, and consumer-complete**: v1.64 persist (`verify-evidence.json`) → annotate (`discover` `Verify:` line) + `metrics` cross-reference; v1.65 `.verified` tier label + verified-first ordering; v1.66 grade (`bothPass` = +50 `Score` signal, `defaultFails` = veto), which overturned the cycle-61/62 "`defaultFails` does not demote" decision; v1.67 grade-before-the-cut; v1.68 wired the last two consumers (`.verified` reaches `DecisionRecord.tier` / `metrics` tier-mix; `drift` excludes verify-disproven picks); v1.70.A extended the `metrics` cross-reference to `--decisions` aggregation mode. **`defaultFails` is execution evidence, not heuristic inference — suppressing a disproven suggestion raises precision.**

**The documented roadmap is empty** (per cycle-67 findings). The pick-closing surface is near-exhausted — the residual 51 `.architectural-coverage-pending` is dominated by internal-API dead ends (`_HashTable*`) and discover-layer false positives the cycle-60 investigation catalogued. No further cycle is scoped; candidate future directions (none currently planned) live in `docs/calibration-cycle-67-findings.md` — PRD §17.2's two new-field metrics, the kit-side `Ring`/`CommutativeGroup` deferrals, incremental index analysis.

Per-cycle narratives live in git log + `docs/archive/v1.N Calibration Plan.md` + `docs/calibration-cycle-N-findings.md` + `docs/calibration-cycle-N-data/`. This file is a pointer-only index. Most recent: `docs/calibration-cycle-67-findings.md`, `docs/calibration-cycle-66-findings.md`.

### Arc summary (how the project got here)

- **v0.1–v1.3 / TemplateEngine M1–M8 + TestLifter M1–M16** — full v1 surface; plans in `docs/archive/`.
- **v1.4–v1.30, cycles 1–27 (mechanism + empirical calibration)** — drove the Possible-tier acceptance rate to 21/29 = **72.4%**, crossing the PRD §19 ≥70% target. Surface reduced ~90.7% vs cycle-1's 1167-baseline. Empirical-only releases: v1.9, v1.17, v1.20, v1.23, v1.26, v1.28, v1.30.
- **v1.31–v1.35 (design-completion releases)** — PRD §20 v1.1 items: FP approximate-equality template arm (v1.31), Domain Template Packs (v1.32), SemanticIndex + `index`/`query` subcommands (v1.33–v1.34), carrier-aware refactor suggestions (v1.35).
- **v1.36–v1.41 (Constraint Engine + cluster classification)** — `Constraint<Subject>` + `ConstraintRunner`, template migration, two-layer dominant-pattern cluster rule (v1.41).
- **v1.42–v1.49 (Phase 1 + 1.5: test-execution-evidence shift)** — `swift-infer verify` pipeline: compiles + runs synthesized property tests in a throwaway SwiftPM workdir. Two-pass edge-case-biased outcomes (`bothPass`/`edgeCaseAdvisory`/`defaultFails`/`error`). Six templates supported; DerivationStrategist verify-time integration; verifiable-fraction reached 87.5%, verifier-mode REJECT lift 8/8.
- **v1.50–v1.63 (Phase 2: full-surface measurement + gap-closing)** — `--all-from-index` survey over the frozen 103-pick cycle-27 surface; 5-category outcome scheme. Key fixes: `libTesting.dylib` DYLD injection (v1.53, first non-zero measurement), per-function generator domains (v1.55), TypeShape scaffolds for OC carriers (v1.58–v1.63), curated dual-style pair fix (v1.61, +12 `.bothPass`). Measured-execution rate climbed 0% → 40.8%.
- **v1.64 (Phase 2 accept-flow integration)** — verify outcomes persist to `.swiftinfer/verify-evidence.json` and flow into `discover` (per-suggestion `Verify:` annotation) and `metrics` (§17.2 cross-reference). The first concrete payoff from the v1.42–v1.63 verify-architecture arc: verify evidence that influences what the user sees.
- **v1.65 (Verified first-class tier)** — `Tier.verified`: a `.strong` suggestion with `.measuredBothPass` evidence promotes to the top tier and floats to the head of the discover stream. Render-time only; no `Score` change.
- **v1.66 (verify-as-signal)** — verify outcomes become a grade input: `bothPass` adds a +50 `Score` signal, `defaultFails` is a veto that suppresses the disproven pick. Overturns the cycle-61/62 "`defaultFails` does not demote" decision (execution evidence ≠ heuristic inference).
- **v1.67 (verify scoring before the visibility cut)** — moves the v1.66 fold inside the discover pipeline, ahead of the visibility filter, so a `bothPass` outcome can rescue a sub-threshold pick; also fixes `combineAndFilter` to never leak `.suppressed` through `--include-possible`.
- **v1.68 (verify evidence reaches its last two consumers, cycle 65)** — `.verified` reaches `DecisionRecord.tier` via interactive triage (so the `metrics` tier-mix reflects it); `drift` loads verify evidence and excludes verify-disproven picks from drift warnings; `Discover.run()`-level integration tests for verify-suppression. The verify-evidence arc becomes consumer-complete.
- **v1.69 (monotonicity-emitter rework, cycle 66)** — instance-method monotonicity composer for OrderedCollections carriers + three nested-OC carrier scaffolds: closes 10 monotonicity picks (`index(after:)` / `index(before:)` over `OrderedSet` / `OrderedDictionary` views), lifting measured-execution 40.8% → 50.5%. Overturns the cycle-60 investigation's "defer indefinitely" conclusion.
- **v1.70 (roadmap cleanup, cycle 67)** — the last two open items: `metrics --decisions` aggregation mode joins per-corpus verify evidence (`VerifyEvidenceLog.merge`); `verify` reindexes the SemanticIndex on demand (V1.42.C.5, deferred 27 cycles — `Index.performIndex` hoisted to a callable static, driven by `Verify.reindexIfNeeded`). The documented roadmap is now empty.

## Kit-side coordination

`Package.swift` pins **SwiftPropertyLaws** at `from: "2.0.0"` (kit renamed from SwiftProtocolLaws at v2.0.0; `ProtocolLawKit`/`ProtoLawCore`/`ProtoLawMacro` → `PropertyLawKit`/`PropertyLawCore`/`PropertyLawMacro`). The verify pipeline (v1.42+) uses the kit's opt-in `PropertyLawComplex` product; the main `PropertyLawKit` line keeps a zero `swift-numerics` footprint. Still deferred kit-side: `Ring` (Numeric stays the canonical writeout target per PRD §5.4 row 5), `CommutativeGroup`, `Group acting on T`.

## What this repo is

**SwiftInferProperties** — type-directed property inference for Swift. Surfaces idempotence, round-trip pairs, and algebraic-structure (semigroup / monoid / group / semilattice / ring) candidates from function signatures, cross-function pairs, and existing unit tests. All output is human-reviewed; nothing auto-executes.

One-way downstream of [SwiftPropertyLaws](https://github.com/Joseph-Cursio/SwiftPropertyLaws):

```
SwiftInferProperties → SwiftPropertyLaws (PropertyBackend, DerivationStrategist) → swift-property-based
```

## Where to look

| Question | File |
|---|---|
| Product scope, milestones, success criteria | `docs/SwiftInferProperties PRD v1.0.md` (canonical) |
| Current milestone plan | None open — see "Repository state" above |
| Current perf baseline | `docs/perf-baseline-v1.N.md` (latest version; prior baselines retained for forensic comparison) |
| Calibration cycle N findings + data | `docs/calibration-cycle-N-findings.md` + `docs/calibration-cycle-N-data/` |
| Triage rubrics | `docs/cycle-6-triage-rubric.md` (canonical per-template criteria) + `docs/cycle-14-triage-rubric.md` |
| Closed milestone + calibration plans | `docs/archive/*.md` |
| PropertyLawKit / PropertyLawMacro source of truth | The SwiftPropertyLaws repo, not this one |

## Design decisions baked into v0.3

These live in the PRD; this is a quick map. Follow them rather than re-litigating.

- **Conservative inference — high precision, low recall.** PRD §3.5. When in doubt, default to fewer suggestions.
- **Opt-in, human-reviewed output.** Never auto-applies/executes/commits. Even CI mode (PRD §9) emits warnings, not failures.
- **Avoid the Daikon trap.** If calibration shows too many suggestions, raise thresholds — don't add filters on top.
- **Three v1 contributions, one v1.1.** TemplateEngine + RefactorBridge + TestLifter ship in v1; SemanticIndex + Constraint Engine + Domain Template Packs + IDE integration + Semantic Linting bridge are PRD §20 v1.1+.
- **Explainability is a first-class output.** Every suggestion ships both "why suggested" and "why this might be wrong." PRD §4.5.
- **Generator inference delegates to SwiftPropertyLaws.** Call `DerivationStrategist`; don't reimplement. PRD §11.

## Build & test

- `swift package clean && swift test` (per global `~/CLAUDE.md`) on session start.
- Skeleton expects `../SwiftPropertyLaws` as a sibling checkout. CI checks both repos out side-by-side.
- Non-subprocess fast path: `swift test --skip VerifyPipelineIntegrationTests` (~4s); full `swift test` is dominated by parallel subprocess builds.
- SwiftLint config at `.swiftlint.yml`; `swiftlint lint --quiet` should be silent.
