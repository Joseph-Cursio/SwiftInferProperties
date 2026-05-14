# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**Current: v1.63.0** — sixtieth calibration cycle; thirteenth Phase 2 gap-closing cycle; **diminishing-returns pivot point**. V1.63.A scaffolds `OrderedDictionary.Elements` via the V1.62.A 3-edit pattern (binding + recipe + gate) — closes 1 `.bothPass` (`OD.Elements.sort()` idempotence). Plus reclassification for `"generic parameter ... could not be inferred"` — preserves `.measured-error = 0`. **Test count 2415.**

**Cycle-60 measurement headline**: **42/103 = 40.8% measured-execution** (+1 vs cycle-59). Distribution: 28 `.bothPass` + 6 `.defaultFails` + 8 `.edgeCaseAdvisory` + 0 `.measured-error` + 61 `.architectural-coverage-pending`. **OC-family coverage**: 22/44 = 50%. Diminishing returns visible: v1.62 closed 8 picks; v1.63 closed 1.

**Per-pick correctness**: 32-pick sample-subset agreement with cycle-46 — strict 4-category match 5/13 = 38%; semantic "property holds" match 13/13 = **100%**. The 13 OS `.bothPass` outcomes extend the measurable set beyond the cycle-46 sample.

v1.64+ priorities (per cycle-59/60 evidence, in priority order):

1. **Comparable-aware monotonicity composer** — broader unblock for remaining nested-OC carriers (OS.SubSequence, OD.Values, OD.Elements.SubSequence), which are dominated by Comparable-blocked monotonicity + discover-layer false-positives.
2. **Strategist recipes for non-OC generics** (17 picks: `_HashTable`, `ChunkedByCollection`, etc.) — V1.62.A 3-edit pattern.
3. **`_minimumCapacity/_maximumCapacity` curated round-trip pair** (3 picks; likely reclassify to internal-api).
4. **Phase 2 accept-flow integration** — demonstrably viable (40% measured rate, 0 measured-error).
5. **Methodology-guard for curated-pair tables** — fixture-level check, V1.58.B-style.
6. **Discover-layer false-positive cleanup** — 4 commutativity/associativity signature-mismatch picks; deferred indefinitely.
7. **V1.42.C.5 deferred** — implicit reindex on demand (carried from v1.42).

Per-cycle narratives live in git log + `docs/archive/v1.N Calibration Plan.md` + `docs/calibration-cycle-N-findings.md` + `docs/calibration-cycle-N-data/`. This file is a pointer-only index. Most recent: `docs/calibration-cycle-59-findings.md`, `docs/archive/v1.62 Calibration Plan.md`.

### Arc summary (how the project got here)

- **v0.1–v1.3 / TemplateEngine M1–M8 + TestLifter M1–M16** — full v1 surface; plans in `docs/archive/`.
- **v1.4–v1.30, cycles 1–27 (mechanism + empirical calibration)** — drove the Possible-tier acceptance rate to 21/29 = **72.4%**, crossing the PRD §19 ≥70% target. Surface reduced ~90.7% vs cycle-1's 1167-baseline. Empirical-only releases: v1.9, v1.17, v1.20, v1.23, v1.26, v1.28, v1.30.
- **v1.31–v1.35 (design-completion releases)** — PRD §20 v1.1 items: FP approximate-equality template arm (v1.31), Domain Template Packs (v1.32), SemanticIndex + `index`/`query` subcommands (v1.33–v1.34), carrier-aware refactor suggestions (v1.35).
- **v1.36–v1.41 (Constraint Engine + cluster classification)** — `Constraint<Subject>` + `ConstraintRunner`, template migration, two-layer dominant-pattern cluster rule (v1.41).
- **v1.42–v1.49 (Phase 1 + 1.5: test-execution-evidence shift)** — `swift-infer verify` pipeline: compiles + runs synthesized property tests in a throwaway SwiftPM workdir. Two-pass edge-case-biased outcomes (`bothPass`/`edgeCaseAdvisory`/`defaultFails`/`error`). Six templates supported; DerivationStrategist verify-time integration; verifiable-fraction reached 87.5%, verifier-mode REJECT lift 8/8.
- **v1.50–v1.63 (Phase 2: full-surface measurement + gap-closing)** — `--all-from-index` survey over the frozen 103-pick cycle-27 surface; 5-category outcome scheme. Key fixes: `libTesting.dylib` DYLD injection (v1.53, first non-zero measurement), per-function generator domains (v1.55), TypeShape scaffolds for OC carriers (v1.58–v1.63), curated dual-style pair fix (v1.61, +12 `.bothPass`). Measured-execution rate climbed 0% → 40.8%.

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
