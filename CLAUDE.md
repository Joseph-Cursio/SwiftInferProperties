# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository state

**Current: v1.74.0** — seventy-first calibration cycle. v1.73 shipped V2.0.M1.A (signature-scan reducer discovery against three canonical shapes); v1.74 ships **V2.0.M1.B** — the TCA conformance walk that closes M1.A's gap on `var body: some ReducerOf<Self>` (not a `FunctionDeclSyntax`, so signature-scan silently misses it). The extended `ReducerDiscoverer.Visitor` tracks `import ComposableArchitecture` per-file, recognizes `Reducer` / `Reducer<...>` / `ReducerOf<...>` inheritance, and walks each conformer's `var body` for `Reduce { state, action in ... }` calls via the new `ReduceClosureWalker` (a recursive SyntaxVisitor that picks up nested `Reduce` calls under `Scope` / `CombineReducers` / similar wrappers). V2.0.M1.B.1 adds the `ReducerCarrierKind` enum (`.generic` / `.tca`; `.elmStyle` reserved for M1.C), the `carrierKind` field on `ReducerCandidate` (default `.generic` so M1.A tests stay green), and a new 4th `ReducerSignatureShape` case `inoutStateActionReturnsEffect` for the TCA synthesized signature. V2.0.M1.B.2 ships the walk + closure extractor. **Test count 2600 → 2618 (+18).**

**Three M1.B decisions settled.** (1) `carrierKind` moved forward from M1.C to M1.B — the first non-`.generic` carrier ships here so the concept arrives organically. (2) New `inoutStateActionReturnsEffect` shape rather than reusing an existing one — TCA closures are genuinely `(inout S, A) -> Effect<A>`, different from M1.A's three shapes. (3) Conservative posture: TCA walk only fires when the file imports `ComposableArchitecture` (matches v1's `@Discoverable` name-match strategy, avoids false matches against unrelated `Reducer` protocols).

**Measured-execution: 52/103 = 50.5%** — carries from cycle 66 unchanged; v1.70–v1.73 touch no v1 emitter/resolver/carrier path. v2.0's own measured-execution metric (PRD §19 Phase 2 target: ≥30% on the v2.0 calibration corpus) is not yet measurable — M3's in-process verify path arrives at a later milestone.

**The verify-evidence arc is complete, internally consistent, and consumer-complete**: v1.64 persist (`verify-evidence.json`) → annotate (`discover` `Verify:` line) + `metrics` cross-reference; v1.65 `.verified` tier label + verified-first ordering; v1.66 grade (`bothPass` = +50 `Score` signal, `defaultFails` = veto), which overturned the cycle-61/62 "`defaultFails` does not demote" decision; v1.67 grade-before-the-cut; v1.68 wired the last two consumers (`.verified` reaches `DecisionRecord.tier` / `metrics` tier-mix; `drift` excludes verify-disproven picks); v1.70.A extended the `metrics` cross-reference to `--decisions` aggregation mode. **`defaultFails` is execution evidence, not heuristic inference — suppressing a disproven suggestion raises precision.**

**PRD §17.2 is complete at 5/5** (acceptance / rejection / suppression rate since V1.4.1; time-to-adoption v1.71; post-acceptance failure rate v1.72). The v1 pick-closing surface stays near-exhausted (residual 51 `.architectural-coverage-pending`, mostly `_HashTable*` internal-API dead ends). v2.0's milestone arc (PRD §5.8) — M1 reducer discovery → M2 ActionSequenceGenerator → M3 in-process verify → M4 lifted families → M5–M7 new families (cardinality / referential integrity / biconditional) → M8 subprocess verify → M9 InteractionInvariantBridge → M10 drift mode — is the new roadmap. M1.A is done; M1.B (TCA `Reducer.body` walk) and M1.C (carrier-kind labeling + `--reducer` pinning + calibration-corpus pin) are next.

Per-cycle narratives live in git log + `docs/archive/v1.N Calibration Plan.md` + `docs/calibration-cycle-N-findings.md` + `docs/calibration-cycle-N-data/`. This file is a pointer-only index. Most recent: `docs/calibration-cycle-71-findings.md`, `docs/calibration-cycle-70-findings.md`.

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
- **v1.71 (time-to-adoption, cycle 68)** — ships PRD §17.2's 4th metric: `metrics` joins accepted decisions against the SemanticIndex (`firstSeenAt` → decision timestamp) for a per-template time-to-adoption summary. No schema-v3 bump — the index already carries the anchors. The 5th §17.2 metric (post-acceptance failure rate) stays parked on an open trigger-design decision.
- **v1.72 (post-acceptance failure rate, cycle 69)** — ships PRD §17.2's 5th and final metric. Resolves the cycle-68 trigger-design decision by shipping a manual `swift-infer accept-check` gesture (V1.72.A subcommand → V1.72.B `post-acceptance-outcomes.json` persistence → V1.72.C metrics section). Four-state classification: `stillPasses` / `nowFails` / `obsolete` (new — function evolved past the suggestion) / `error`. Rate excludes `obsolete` + `error` from the denominator and surfaces a selection-bias caveat in the §17.2 section. No `Decisions` schema bump — parallel `.swiftinfer/` file, same pattern as `verify-evidence.json`.
- **v1.73 (V2.0.M1.A reducer discovery, cycle 70)** — **first non-v1 cycle**. Pivots from the empty v1 roadmap to v2.0 — interaction-invariant inference for SwiftUI state systems. Ships M1.A foundation: `swift-infer discover-reducers` subcommand detects functions matching three canonical reducer shapes (PRD v2.0 §6.2). Signature-only — no carrier-kind labeling yet (M1.C), no TCA `Reducer.body` walk yet (M1.B), no scoring yet (M4+). Resolves three open scoping decisions: separate subcommand (not `discover --reducers`), strict Action surface (PRD §21 #2), and version-bump cadence continued.
- **v1.74 (V2.0.M1.B TCA conformance walk, cycle 71)** — closes M1.A's blind spot. TCA's `var body: some ReducerOf<Self>` isn't a `FunctionDeclSyntax`, so signature-scan misses it. v1.74 adds an inheritance-clause check (`Reducer` / `Reducer<…>` / `ReducerOf<…>`) gated on `import ComposableArchitecture`, then walks the conformer's `var body` for `Reduce { state, action in ... }` closures via the new `ReduceClosureWalker`. Each match emits one candidate with `carrierKind: .tca` and a new 4th signature shape `inoutStateActionReturnsEffect`. Three M1.B-scoping decisions resolved: carrierKind moved forward from M1.C, new shape case (not reused), conservative import gating.

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
