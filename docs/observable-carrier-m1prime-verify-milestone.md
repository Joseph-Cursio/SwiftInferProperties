# Milestone — Execution-backed verify for `@Observable` carriers (M1′ live path)

**Status:** Draft / proposal — not yet scheduled.
**Author context:** written after the Observable Carrier "thread 1" work (materialize the action enum, M1′ live-class). Slices 1–3b + the same-target groundwork have shipped; this milestone promotes that emitter from a measured-test engine into the live inference loop.
**Relates to:** `docs/ideas/Observable Carrier Proposal.md`, `docs/measured-verify-architecture.md`, PRD §3.5 (ViewModel suggestions as an inference source), PRD §5 (interaction families).

---

## 1. What already shipped (the engine)

The synthetic-Action-enum path is built and proven end-to-end:

- **`ViewModelActionEnumEmitter`** — lifts an `@Observable` model's mutating methods into `enum <Type>Action` + `drive(_ model, _ action)`. Labelled multi-arg cases, collision-safe case names, keyword escaping, `async`/`throws` dropped with a reason, `CaseIterable` when nullary-only.
- **`ViewModelActionSequenceStubEmitter`** — the M1′ verifier: enum + `drive` + kit `ActionSequenceFactory.actionSequence(...)` + a **fresh live probe per trial** + prefix replay + per-step invariant check + the `VERIFY_*` marker contract. Nullary surfaces enumerate via `forCaseIterable:`; payloaded surfaces (Slice 3b) compose a `Gen<Action>` over the constructible subset (`Gen.always(.case)` / `<RawType gen>.map(Enum.case)`), disclosing non-constructible cases.
- **Same-target groundwork** — `Inputs.userModuleName: String?` (nil ⇒ no `import`), so the model can be compiled *into* the verifier target (`VerifierWorkdir` `.interaction` + `inlinedSources`).

Proven in a kit-linked scratch package: clean model → `PASS`/100 trials; planted invariant breaks → `FAIL` at the first offending sequence, for both the nullary and payloaded paths.

## 2. The gap this milestone closes

Today the two carrier families are asymmetric:

| | Reducers (TCA / Elm / …) | `@Observable` view models |
|---|---|---|
| Discovery | `ReducerDiscoverer` | `ViewModelDiscoverer` ✓ |
| Static suggestion | `InteractionInvariantSuggestion` | `mergedWithViewModels` → `ViewModelInteractionAnalyzer.suggestions` ✓ (at `.possible`) |
| **Execution-backed verify** | `VerifyInteractionPipeline` (emit → build → run → promote `.possible` → `.verified`/refute) ✓ | **none in the live path** — only measured tests exercise the single-pass `ViewModelInvariantStubEmitter` |

So a ViewModel interaction invariant can be *surfaced* but never *confirmed by running it*. Reducers get the full "empirical evidence, not a guess" treatment; view models stop at a static guess. **This milestone gives `@Observable` carriers the same execution-backed confirmation, using the M1′ emitter as the engine** — and the single-pass emitter is retired from the intended live path (it stays only as the deprecated dependency-free fallback if we choose to keep it).

## 3. Design

### 3.1 Routing

Extend the interaction-verify path so a `ViewModelCandidate` + its resolved predicate flows through an execution pass parallel to the reducer one. Two options:

- **(A) A sibling `ViewModelVerifyInteractionPipeline`** — the cleanest separation; reuses `VerifierWorkdir` / `VerifierSubprocess` / `VerifyResultParser` but keeps ViewModel specifics (predicate resolvers, inlined-model workdir) out of the reducer pipeline.
- **(B) A carrier-kind branch inside `VerifyInteractionPipeline`** — less code, but couples two carrier shapes in one type.

**Recommendation: (A)**, mirroring how discovery kept `ViewModelDiscoverer` separate from `ReducerDiscoverer` rather than folding `observable` into `ReducerCarrierKind`. The shared machinery (workdir synth, subprocess, marker parse, confidence promotion) is called, not reimplemented.

### 3.2 The verify step (per candidate × family)

1. **Resolve the predicate** over a `probe` from the existing resolvers: `ViewModelRefintResolver`, `ViewModelCardinalityResolver`, `ViewModelBiconditionalResolver`, `ViewModelConservationResolver` (+ the idempotence path). A `nil` resolution ⇒ skip (unverifiable), disclosed.
2. **Gate on constructibility** — `candidate.constructibility == .zeroArgument` (the verifier must build `Type()`); otherwise skip with the injected-dependency disclosure. (Dependency-faked construction is a later widening — the `ViewModelDependencyConstructor` / `ViewModelProtocolFaker` infra already exists.)
3. **Emit** via `ViewModelActionSequenceStubEmitter` with `userModuleName: nil` and `actions: candidate.actions` — the emitter is already candidate-shaped:
   ```swift
   ViewModelActionSequenceStubEmitter.Inputs(
       typeName: candidate.typeName,
       userModuleName: nil,                 // inlined into the verifier target
       predicate: resolved.predicate,
       actions: candidate.actions
   )
   ```
   Handle the two throws: `.emptyActionSurface` / `.noConstructibleActions` ⇒ skip-with-reason (no execution possible), surfaced in the disclosure like the reducer path's excluded set.
4. **Synthesize the workdir** — `VerifierWorkdir.synthesize` in `.interaction` mode, with the candidate's source file(s) in `inlinedSources` (so the model is in-module and `Verifier.swift` carries `@main`). No `userPackage` needed.
5. **Build + run** — `VerifierSubprocess.runSwiftBuild` then `runVerifierBinary` (which already injects the `libTesting` / `Testing.framework` DYLD paths, V1.53.A — the exact runtime the kit-linked stub needs).
6. **Parse + promote** — `VerifyResultParser.parse` → `VerifyOutcome`; `.bothPass`/`PASS` promotes the suggestion `.possible → .verified`, `.defaultFails`/`FAIL` records a refutation/counterexample; build failure → `.error` (disclosed, not a false verdict).

### 3.3 What the multi-step path buys over single-pass

The retired `ViewModelInvariantStubEmitter` drives each action **once**. The M1′ path draws random `[Action]` sequences (length `0…16`) and checks after every step, so it reaches ordered interleavings (`add; select; remove`) — the class of interaction bug this whole line targets. Concretely, the payloaded scratch run caught a negative-count bug only via a multi-action sequence, at trial 1; a single pass over `{reset, setCount(0)}` would miss it.

## 4. Slices

1. **`ViewModelVerifyInteractionPipeline`** — the routing + per-candidate verify step (§3.2), returning promoted suggestions. Unit-tested with a stubbed subprocess (inject a fake `VerifyOutcome`) so the routing/promotion logic is covered without a real build.
2. **Corpus source plumbing** — expose the candidate's originating `.swift` file(s) as `inlinedSources`. `ViewModelDiscoverer` already tracks `location` (`<path>:<line>`); thread the file URL through so the pipeline can inline it.
3. **Measured integration test** — mirror `RefIntVerifyCorpusMeasuredTests`: for a clean and a buggy fixture, emit → `.interaction` workdir (inlined) → build → run → assert `.bothPass` / `.defaultFails`. Tagged `.subprocess`. Reuse `viewmodel-refint-corpus` (`SafeCatalogModel` vs `CatalogModel`).
4. **Live wiring** — call the pipeline from `verify-interaction` for the ViewModel-sourced suggestions, so a real `swift-infer verify-interaction` confirms/refutes them.

## 5. Calibration plan (the load-bearing part)

This is why the milestone is *measured*, not a code flip. The seven ViewModel corpora (`viewmodel-verify-corpus`, `viewmodel-refint-corpus`, `viewmodel-invariant-corpus`, `viewmodel-keyed-refint-corpus`, `viewmodel-faked-dep-corpus`, `viewmodel-package-corpus`, `refint-verify-corpus`) are the calibration surface.

- **Precision guardrail (the Daikon trap).** Multi-step exploration reaches states the single pass never did — so a previously-"passing" invariant may now legitimately fail, *or* may false-fail if the predicate/model construction is wrong. Before promoting M1′ to the default, run both emitters over every corpus and diff outcomes. Every M1′ `FAIL` that single-pass `PASS`ed must be **hand-classified** as a real bug (good — that's the whole point) or a false positive (fix the resolver/predicate or gate the case). Hold the per-family precision bar from PRD §5; raise thresholds, don't pile on filters.
- **Baseline metric.** Record the per-corpus verified/refuted/skipped counts for M1′ separately from the reducer corpus, so the ViewModel acceptance-rate curve is measured independently (the Observable Carrier proposal §5 already asks for this).
- **Sequence budget.** `0…16` is the reducer default; measure whether a large action alphabet needs per-carrier tuning before touching it (proposal open Q #4 — measure first).

**Promotion criterion:** M1′ becomes the live ViewModel verify default only once the corpus diff shows **no unexplained false positives** and coverage ≥ the single-pass path on the shared corpora.

## 6. Risks & non-goals

- **Reference-type State.** M1′ deliberately drives a *live* class (no synthetic value-`State` projection). Fresh probe per trial keeps trials independent; there is no cross-trial state leak to reason about. (The value-`State`/`checkInteractionInvariant` route — "M2" — stays explicitly out of scope.)
- **Effectful methods.** Models that spawn `Task`/await are common; those actions are already dropped (`async`) with disclosure. Broadening to effect-bearing methods (subprocess isolation) is a later milestone, not this one.
- **Payload reach.** Slice 3b covers raw scalars. `UUID` / optionals / memberwise-generatable structs are follow-ups (delegate to `DerivationStrategist`), disclosed as excluded meanwhile — never silently dropped.
- **Not** auto-applying anything; not inferring actions from view code; not touching the kit (SwiftPropertyLaws). All output stays suggestion-level and human-reviewed.

## 7. Acceptance criteria

1. `swift-infer verify-interaction` confirms/refutes `@Observable`-sourced interaction invariants via the M1′ emitter, promoting `.possible → .verified` on a clean multi-step run and recording a counterexample on a failing one.
2. A `.subprocess` measured test proves the full emit → `.interaction` workdir → build → run → promote loop on a clean and a buggy fixture.
3. A documented corpus diff (M1′ vs single-pass across the seven corpora) shows no unexplained false positives, recorded in a calibration note alongside the acceptance-rate baseline.
4. The single-pass `ViewModelInvariantStubEmitter` is removed from the live path (kept only as a documented fallback, or deleted).
