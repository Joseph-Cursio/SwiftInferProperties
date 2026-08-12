# Milestone — Execution-backed verify for `@Observable` carriers (M1′ live path)

> **Status:** `shipped` · **As of:** 2026-08-07


**Status:** **Largely implemented — calibration gate cleared.** S1–S4 shipped (`ViewModelVerifyInteractionPipeline` + `…Survey`, measured proof, live wiring into `verify-interaction --all`). The 7-corpus diff (§5.1) found **zero false-positive REFUTEs**, so M1′ was wired live. Remaining: imported-path end-to-end fixture, keyed-refint resolution, and evidence-tier fold-back (§7).
**Author context:** written after the Observable Carrier "thread 1" work (materialize the action enum, M1′ live-class), then updated with the as-built record + calibration results. Slices 1–3b + the same-target groundwork shipped first; this milestone promoted that emitter from a measured-test engine into the live inference loop.
**Relates to:** the Observable Carrier Proposal (`docs/ideas/Observable Carrier Proposal.md`, removed in `c5c685b` once implemented; recover with `git show c5c685b^:"docs/ideas/Observable Carrier Proposal.md"`), `docs/design/measured-verify-architecture.md`, PRD §3.5 (ViewModel suggestions as an inference source), PRD §5 (interaction families).

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
4. **Synthesize the workdir** — `VerifierWorkdir.synthesize` in `.interaction` mode. Two shapes: **inlined** (self-contained corpora — model file(s) in `inlinedSources`, `userModuleName: nil`, no `userPackage`) and **imported** (real user packages — `userPackage` path-dependency + `userModuleName: <module>` so the stub imports it, no `inlinedSources`). The measured test uses inlined; the live `verify-interaction --all` wiring uses imported (as built).
5. **Build + run** — `VerifierSubprocess.runSwiftBuild` then `runVerifierBinary` (which already injects the `libTesting` / `Testing.framework` DYLD paths, V1.53.A — the exact runtime the kit-linked stub needs).
6. **Parse + promote** — `VerifyResultParser.parse` → `VerifyOutcome`; `.bothPass`/`PASS` promotes the suggestion `.possible → .verified`, `.defaultFails`/`FAIL` records a refutation/counterexample; build failure → `.error` (disclosed, not a false verdict).

### 3.3 What the multi-step path buys over single-pass

The retired `ViewModelInvariantStubEmitter` drives each action **once**. The M1′ path draws random `[Action]` sequences (length `0…16`) and checks after every step, so it reaches ordered interleavings (`add; select; remove`) — the class of interaction bug this whole line targets. Concretely, the payloaded scratch run caught a negative-count bug only via a multi-action sequence, at trial 1; a single pass over `{reset, setCount(0)}` would miss it.

## 4. Slices (as built)

1. **`ViewModelVerifyInteractionPipeline`** ✅ — routing + per-candidate verify step (§3.2) → `StepResult` (`.ran(VerifyOutcome)` / `.skipped(reason)`). Build+run is an **injected `VerifyRunner`** (not a stubbed subprocess as first sketched), so routing/gating/emit is unit-tested without a real build; `liveRunner()` (inlined) and `importedRunner(userPackage:)` (real package) are the production seams.
2. **Corpus source plumbing** ✅ — covered by the existing `CorpusPackager.readSwiftSources(in:)`; no new code needed.
3. **Measured integration test** ✅ — `ViewModelM1PrimeVerifyMeasuredTests` (`.subprocess`): emit → `.interaction` workdir (inlined) → build → run over `viewmodel-refint-corpus`. `SafeCatalogModel` → `.ran(.bothPass)`; `CatalogModel.toggle(Int)` → `.ran(.defaultFails)`. Passes ~36s.
4. **Live wiring** ✅ — `ViewModelVerifyInteractionSurvey` (resolve every family predicate per candidate → verify → `VERIFIED`/`REFUTED` verdicts) is called from `verify-interaction --all` as an additive pass after the reducers (guarded with `try?`). Uses the **imported** workdir shape for real packages (`userModuleName` + `importedRunner` + `PackageProductResolver.libraryProduct`, reused from the reducer path).

## 5. Calibration plan (the load-bearing part)

This is why the milestone is *measured*, not a code flip. The seven ViewModel corpora (`viewmodel-verify-corpus`, `viewmodel-refint-corpus`, `viewmodel-invariant-corpus`, `viewmodel-keyed-refint-corpus`, `viewmodel-faked-dep-corpus`, `viewmodel-package-corpus`, `refint-verify-corpus`) are the calibration surface.

- **Precision guardrail (the Daikon trap).** Multi-step exploration reaches states the single pass never did — so a previously-"passing" invariant may now legitimately fail, *or* may false-fail if the predicate/model construction is wrong. Before promoting M1′ to the default, run both emitters over every corpus and diff outcomes. Every M1′ `FAIL` that single-pass `PASS`ed must be **hand-classified** as a real bug (good — that's the whole point) or a false positive (fix the resolver/predicate or gate the case). Hold the per-family precision bar from PRD §5; raise thresholds, don't pile on filters.
- **Baseline metric.** Record the per-corpus verified/refuted/skipped counts for M1′ separately from the reducer corpus, so the ViewModel acceptance-rate curve is measured independently (the Observable Carrier proposal §5 already asks for this).
- **Sequence budget.** `0…16` is the reducer default; measure whether a large action alphabet needs per-carrier tuning before touching it (proposal open Q #4 — measure first).

**Promotion criterion:** M1′ becomes the live ViewModel verify default only once the corpus diff shows **no unexplained false positives** and coverage ≥ the single-pass path on the shared corpora.

### 5.1 Calibration results (measured)

Ran the M1′ survey (`liveRunner`, inlined) across all seven corpora. Verdicts:

| Corpus | Model . family | M1′ verdict | Classification |
|---|---|---|---|
| refint | SafeCatalogModel . refint | VERIFIED (100) | ✅ correct |
| refint | CatalogModel . refint | REFUTED (t0) | ✅ real bug |
| invariant | RouterModel . cardinality | VERIFIED (100) | ✅ correct |
| invariant | **LeakyRouterModel . cardinality** | **REFUTED (t1)** | ✅ **real bug — multi-step (`showAlert; showSheet`); single-pass can't reach** |
| invariant | SessionModel . biconditional | VERIFIED (100) | ✅ correct |
| invariant | DriftModel . biconditional | REFUTED (t0) | ✅ real bug |
| invariant | CartModel . conservation | VERIFIED (100) | ✅ correct |
| invariant | BadgeModel . conservation | REFUTED (t0) | ✅ real bug (`clearItems` skips `itemCount`) |
| verify | SelectionModel . refint | VERIFIED (100) | ✅ correct (post-fix; see below) |
| faked-dep / package | LibraryModel . refint | skipped | ✅ correct (constructibility gate — `requires store`) |
| keyed-refint | Ghost/SafePlaylist | not resolved | ⚠️ coverage gap (below) |

**Verdict: zero false-positive REFUTEs** — every REFUTED is a genuine invariant break by corpus design, and M1′ caught a real bug (`LeakyRouterModel`) that single-pass's one-action-at-a-time drive structurally cannot. The promotion criterion is met, so M1′ was wired live.

Two findings the diff surfaced:

- **Fixed — integer-payload overflow trap.** `SelectionModel.setStep(_ n: Int)` accumulates `cursor = cursor + n`; the unbounded `Gen<Int>.int()` payload overflow-trapped the verifier subprocess (exit 5) over a 16-step sequence — a generator-domain crash, *not* an invariant break. Integer payloads now use the kit's `boundedForArithmetic()` (magnitude `2^(bitWidth/4)`), which still reaches the out-of-range / negative / zero values that falsify membership. Re-run → `SelectionModel` VERIFIED, every other verdict unchanged. (This is the calibration mechanism working as intended.)
- **Coverage gap (false negative, not a false positive) — keyed refint.** `ViewModelRefintResolver.resolve` returns `nil` for the scalar-key-over-`Identifiable` shape (`selectedTrackID: Int?` over `[Track]`), so `GhostPlaylistModel`'s real bug isn't caught. Single-pass covers this via its keyed path; wiring keyed-refint resolution into the survey is a follow-up for full parity.

## 6. Risks & non-goals

- **Reference-type State.** M1′ deliberately drives a *live* class (no synthetic value-`State` projection). Fresh probe per trial keeps trials independent; there is no cross-trial state leak to reason about. (The value-`State`/`checkInteractionInvariant` route — "M2" — stays explicitly out of scope.)
- **Effectful methods.** Models that spawn `Task`/await are common; those actions are already dropped (`async`) with disclosure. Broadening to effect-bearing methods (subprocess isolation) is a later milestone, not this one.
- **Payload reach.** Slice 3b covers raw scalars. `UUID` / optionals / memberwise-generatable structs are follow-ups (delegate to `DerivationStrategist`), disclosed as excluded meanwhile — never silently dropped.
- **Not** auto-applying anything; not inferring actions from view code; not touching the kit (SwiftPropertyLaws). All output stays suggestion-level and human-reviewed.

## 7. Acceptance criteria

1. ✅ `swift-infer verify-interaction --all` execution-backs `@Observable`-sourced interaction invariants via the M1′ emitter, rendering `VERIFIED` (the `.possible → .verified` promotion) on a clean multi-step run and `REFUTED` + counterexample on a failing one. *(Render-level promotion; persisting to the evidence tier is item 6.)*
2. ✅ A `.subprocess` measured test (`ViewModelM1PrimeVerifyMeasuredTests`) proves the full emit → `.interaction` workdir → build → run loop on a clean and a buggy fixture.
3. ✅ The corpus diff (§5.1) across the seven corpora shows **no unexplained false positives**; results recorded here.
4. ⏸ The single-pass `ViewModelInvariantStubEmitter` is *not yet* removed — it is retained until the imported-path e2e (item 5) lands, then it becomes a documented fallback or is deleted.

> **Closed out 2026-08-07 — items 5/6/7 all shipped, and 4 resolved to neither
> option it offered.** Item 5 landed as `d74fb71` + `ViewModelPackageVerifyMeasuredTests`,
> item 6 as `c7b7626` + `ViewModelVerifyEvidence.swift` + `ViewModelVerifyEvidenceJoinMeasuredTests`,
> item 7 as `0af9b75` + `ViewModelKeyedRefintVerifyMeasuredTests`. Item 4's premise
> dissolved instead: `ViewModelInvariantStubEmitter` was not demoted to a fallback
> and not deleted — it was **rewritten** into a randomized multi-step sequence
> verifier with a shrink primitive, so it is now a second independent verifier
> beside the M1′ materialized-enum path, not a legacy single pass. **The question
> the box was tracking stopped existing, which is why nobody ticked it** — an
> unchecked box that has been overtaken reads identically to one that is still
> waiting, and this milestone was filed as live work on 2026-08-07 on the strength
> of it.

> **Item 6's ✅ was WRONG — corrected 2026-08-12 at `a3959f0`, and FIXED the same day (§8.1). See §8.** The commit it
> cites, `c7b7626`, added `ViewModelVerifyEvidence.swift` and two test files and **no
> production call site**; nothing in `Sources/` has ever called the recorder. The live
> chain (`VerifyInteractionCommand.swift:197` → `ViewModelVerifyInteractionSurvey.runLive`
> → print) contains zero evidence writes, so promotion is still render-level and item 6's
> own text below — "Promotion is currently render-level" — remained true the whole time.
> **The older detail was right and the newer summary was wrong**, the reverse of the stale-
> summary shape this repo keeps meeting, and neither reading is checkable from prose alone.

**Remaining before "done":**

5. **Imported-path e2e.** The live command uses the *imported* workdir shape (real user package via `.package(path:)` + module import); the code compiles and reuses the reducer path's resolution helpers, but there is no measured test against a real library-product package yet. Add one (a fixture package exposing an `@Observable` module) to prove the imported path end-to-end.
6. **Evidence-tier fold-back.** Promotion is currently render-level. Persist the outcome to `verify-evidence.json` (as reducers do via `recordEvidence`) so `discover-interaction` re-tiers the ViewModel suggestion — closing the discover → verify → re-tier loop.
7. **Keyed-refint resolution** (§5.1) for single-pass parity.

## 8. What `make dead-code` found — 2026-08-12, at `a3959f0`

Prompted by nothing more than running `make dead-code` and asking what the
**test-only** verdict covered. Four `ViewModel*` files sit in that bucket, and they
turned out to be two unrelated findings, neither of which is visible from this doc's
own status line.

### 8.1 Item 6 never shipped — the loop is open

`ViewModelVerifyEvidence` (68L) was added by `c7b7626` (2026-06-18) together with
`ViewModelVerifyEvidenceTests` and `ViewModelVerifyEvidenceJoinMeasuredTests`, and
**with no production caller**. Both surviving `Sources/` mentions of the name are `///`
doc comments (in `SeedEffectResolver` and `OutputDeterminismVerifyEvidence`) — which is
why a raw grep reads it as live, and exactly the comment-stripping rule `make dead-code`
was built on. It has been test-only since the day it was written.

Contrast the reducer path, which persists at four call sites, the survey-level one being
`VerifyInteractionSurvey.swift:143`'s `recordEvidenceBatch`. Grepping the whole live
ViewModel chain — `ViewModelVerifyInteractionSurvey` and `ViewModelVerifyInteractionPipeline`
— for evidence writes returns **none**.

**The guard is what hid it.** `ViewModelVerifyEvidenceJoinMeasuredTests` calls
`ViewModelVerifyEvidence.record(...)` *itself* at `:48` and `:53`, then reads the store
back. It genuinely proves the recorder and the round-trip; it never drives the command,
so a suite named for the join does not exercise the join. A measured, subprocess-tagged,
green test — the `test-only` verdict earning its keep, since a passing suite makes dead
code look maintained.

**FIXED 2026-08-12, hours after being recorded — `ViewModelVerifyInteractionSurvey.foldBack`
+ `ViewModelVerifyEvidence.recordBatch`, called from `runLive`.** Three things about the fix
are worth more than the wiring, which is four lines.

**The pairing is not "record what you verified", because it cannot be.** Evidence is keyed by
`SuggestionIdentity`, whose canonical input is `family::reducerQualifiedName::subjects` — so a
record joins only if it carries the identity the *discover* side computes. This survey resolves
an **executable** predicate (`ViewModelCardinalityResolver` renders a Swift expression over
`probe`), which is a different string from the analyzer's subject list. Re-deriving the identity
here would have been a fifth enumeration of one fact, so the suggestions are asked for
(`ViewModelInteractionAnalyzer.suggestions`) rather than reconstructed.

**The exactly-one rule is a soundness gate, and it costs recall on purpose.**
`referentialIntegrity`, `conservation` and `biconditional` may each surface *several*
suggestions per candidate while the resolvers return at most one predicate per family — so
`(type, family)` does not identify an invariant. A verdict whose key is ambiguous is withheld
and **disclosed in the render**, never guessed: recording under a guessed key would promote to
`.verified` a law that was never run, and of the two failure directions only under-claiming is
recoverable.

**The falsifier this section shipped with named nothing that was built.** It said
`viewModelEvidenceFoldBack`; the function is `foldBack`, so `DeferralFalsifierTests` would have
stayed green forever while the deferral read as open — `nestedCarrierImportResolution`'s exact
failure mode, reproduced within hours of citing it, by the person citing it. It is removed
rather than repointed, because the deferral is closed.

**The guard is the part that had to be different.** The pre-existing
`ViewModelVerifyEvidenceJoinMeasuredTests` proved the recorder worked *by calling it directly*,
which is precisely why it could not notice that nothing else did. `ViewModelEvidenceFoldBackTests`
drives `runLive` instead, with an injected runner so no `swift build` is spawned (the seam is new,
and is the reason the whole chain is now cheap to exercise at all). Checked by mutation, not by
reading: reverting `runLive` to render-only makes 3 of the 7 arms fail with an empty store, the
pre-fix state exactly. One arm asserts the recorded identities are a **subset of what the discover
side computes**, since a record with a plausible-looking key that joins nothing is the failure this
whole section is about.

**Two bounds stated rather than fixed.** Interaction evidence has no staleness gate —
`InteractionVerifyEvidenceScoring` reads no `subjectFingerprint`, so §10.8's protection on the
algebraic path does not cover this one, and a ViewModel verdict persists across an edit to the
model it measured. And idempotence still does not fold back at all, for the reason in §8.2: the
survey never resolves that family, though `discover-interaction` surfaces it.

### 8.2 The idempotence prototype is NOT superseded — it is unadoptable

The first reading of the other three files was that `ViewModelIdempotenceStubEmitter`
(158L) + `ViewModelDependencyConstructor` (84L) + `ViewModelArgumentGenerator` (62L) are a
June prototype overtaken by the July M1′ path, and should be deleted — the
`ParadigmDiscoverer` shape from `docs/design/stateful-role-discoverer-design.md` again.
**That reading was wrong, and it was reached from the dates and this doc's framing rather
than from the two emitters' contracts.** Comparing the contracts kills it on two axes:

| | prototype `ViewModelIdempotenceStubEmitter` | live `ViewModelActionSequenceStubEmitter` |
|---|---|---|
| model construction | `construction: String?` — accepts an injected expression | hardcodes `let probe = TypeName()` (`:266`); **0** occurrences of construction / dependency / faker |
| law checked | state-level `f(f(x)) == f(x)`, plus the x-curried single-arg form | an invariant `predicate` over random `[Action]` sequences |

And the live survey resolves four families — `referential-integrity`, `cardinality`,
`biconditional`, `conservation`. **Idempotence is not among them.**

So routing through the live emitter loses *both* the dependency-injected construction and
the idempotence law. That is `StatefulRole`'s lossiness argument with the polarity
reversed: the superseded-looking file is the one with the richer capability, which makes
it **unadoptable, not merely unadopted**. Two consequences worth stating plainly:

1. The live `verify-interaction` path can only verify a **zero-arg-constructible** view
   model. **This half is deliberate and was already recorded** — §3.2 step 2 above gates on
   `candidate.constructibility` and calls dependency-faked construction "a later widening",
   and the gate is really there, at `ViewModelVerifyInteractionPipeline.swift:56`, skipping
   `.requiresArguments` **with a disclosure**. So the finding is narrower than it first
   looked: not an unnoticed gap but a **widening that never happened**, whose machinery
   (`ViewModelProtocolFaker` + `ViewModelDependencyConstructor`) has sat reachable only from
   tests since June. Worth saying because §3.2 asserts the infra "already exists" as though
   that were most of the work; the emitter it would have to feed does not take a
   construction, so the widening is a change to the **live emitter**, not just plumbing.
2. The idempotence half is **not** covered by an existing decision. §3.2 step 1 lists the
   resolvers "(+ the idempotence path)" — and there is no `ViewModelIdempotenceResolver` in
   `Sources/`; the five that exist are `ViewModelInvariantResolver` plus the refint /
   cardinality / biconditional / conservation four. The only thing that checks view-model
   idempotence is the prototype emitter, from a measured test. So CLAUDE.md's "all five
   have a demonstrated measured-verify path" holds for the **measured-suite** reading and
   not for the live command, on the MVVM carrier specifically.

Deleting the cluster was scoped and **declined on this evidence**: it would have removed
the only implementation of dependency-injected view-model construction, and taken with it
six measured suites (848 lines), three of whose subjects are live code
(`ViewModelRefintResolver`, the cardinality / biconditional / conservation resolvers via
the live `ViewModelInvariantStubEmitter`) and which merely *use* `ViewModelArgumentGenerator`
as a helper. No code was changed.

Refuted when the live emitter can construct a dependency-injected probe
(falsifier: `ViewModelActionSequenceStubEmitter.dependencyInjectedProbeConstruction`) and
when the live survey resolves the fifth family
(falsifier: `ViewModelVerifyInteractionSurvey.viewModelIdempotenceFamily`).

**Both of those are the *fragile* falsifier shape** — a new local name invented at
deferral time, the third of the four grades in
`docs/measurements/falsifier-naming-failure-modes.md`, and they go inert if whoever
fixes this picks a different name (`construction` is the obvious one, and it already
resolves against the prototype, so it cannot be used while the prototype stands). The
witness that cannot go inert is the plainer one: **a `@Observable` carrier with an
injected protocol dependency, surveyed by `verify-interaction --all`, that reaches a
verdict instead of being skipped.**
